#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "This script is intended to run in GitHub Actions (see .github/workflows/yolo-update.yml). Refusing to run locally." >&2
  exit 1
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/nix/sources/openclaw-source.nix"
app_file="$repo_root/nix/packages/openclaw-app.nix"
config_options_file="$repo_root/nix/generated/openclaw-config-options.nix"
flake_lock_file="$repo_root/flake.lock"

upstream_main_sha=$(git ls-remote https://github.com/openclaw/openclaw.git refs/heads/main | awk '{print $1}' || true)

log() {
  printf '>> %s\n' "$*"
}

build_with_hash_refresh() {
  local attr="$1"
  local label="$2"
  local build_log
  local pnpm_hash

  build_log=$(mktemp)
  log "Building ${label}"
  if ! nix build ".#${attr}" --accept-flake-config >"$build_log" 2>&1; then
    pnpm_hash=$(grep -Eo 'got: *sha256-[A-Za-z0-9+/=]+' "$build_log" | head -n 1 | sed 's/.*got: *//' || true)
    if [[ -n "$pnpm_hash" ]]; then
      log "pnpmDepsHash mismatch detected: $pnpm_hash"
      perl -0pi -e "s|pnpmDepsHash = \"[^\"]*\";|pnpmDepsHash = \"${pnpm_hash}\";|" "$source_file"
      if ! nix build ".#${attr}" --accept-flake-config >"$build_log" 2>&1; then
        tail -n 200 "$build_log" >&2 || true
        rm -f "$build_log"
        return 1
      fi
    else
      tail -n 200 "$build_log" >&2 || true
      rm -f "$build_log"
      return 1
    fi
  fi

  rm -f "$build_log"
  return 0
}

upstream_checks_green() {
  local sha="$1"
  local checks_json
  checks_json=$(gh api "/repos/openclaw/openclaw/commits/${sha}/check-runs?per_page=100" 2>/dev/null || true)
  if [[ -z "$checks_json" ]]; then
    log "No check runs found for $sha"
    return 1
  fi

  local relevant_count
  relevant_count=$(printf '%s' "$checks_json" | jq '[.check_runs[] | select(.name | test("windows"; "i") | not)] | length')
  if [[ "$relevant_count" -eq 0 ]]; then
    log "No non-windows check runs found for $sha"
    return 1
  fi

  local failing_count
  failing_count=$(
    printf '%s' "$checks_json" | jq '[.check_runs[]
      | select(.name | test("windows"; "i") | not)
      | select(.status != "completed" or (.conclusion != "success" and .conclusion != "skipped"))
    ] | length'
  )
  if [[ "$failing_count" -ne 0 ]]; then
    log "Non-windows checks not green for $sha"
    return 1
  fi

  return 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

log "Bumping nix-steipete-tools (best-effort)"
if ! nix flake update --update-input nix-steipete-tools --accept-flake-config; then
  log "nix-steipete-tools bump failed; restoring flake.lock and continuing"
  git restore --worktree "$flake_lock_file" 2>/dev/null || true
fi

# Best-effort openclaw bump: if it fails, restore any partial edits and keep the
# (possibly successful) nix-steipete-tools bump.
log "Bumping openclaw pins (best-effort)"
openclaw_backup_dir=$(mktemp -d)
cp "$source_file" "$openclaw_backup_dir/$(basename "$source_file")"
cp "$app_file" "$openclaw_backup_dir/$(basename "$app_file")"
if [[ -f "$config_options_file" ]]; then
  cp "$config_options_file" "$openclaw_backup_dir/$(basename "$config_options_file")"
fi

openclaw_bump_failed=0

if (
  set -euo pipefail

  log "Resolving openclaw main SHAs"
  mapfile -t candidate_shas < <(gh api /repos/openclaw/openclaw/commits?per_page=50 | jq -r '.[].sha' || true)
  if [[ ${#candidate_shas[@]} -eq 0 ]]; then
    latest_sha=$(git ls-remote https://github.com/openclaw/openclaw.git refs/heads/main | awk '{print $1}' || true)
    if [[ -z "$latest_sha" ]]; then
      echo "Failed to resolve openclaw main SHA" >&2
      exit 1
    fi
    candidate_shas=("$latest_sha")
  fi

  selected_sha=""
  selected_hash=""
  selected_source_store_path=""
  selected_source_url=""

  for sha in "${candidate_shas[@]}"; do
    if ! upstream_checks_green "$sha"; then
      continue
    fi
    log "Testing upstream SHA: $sha"
    source_url="https://github.com/openclaw/openclaw/archive/${sha}.tar.gz"
    log "Prefetching source tarball"
    source_prefetch=$(
      nix --extra-experimental-features "nix-command flakes" store prefetch-file --unpack --json "$source_url" 2>"/tmp/nix-prefetch-source.err" \
        || true
    )
    if [[ -z "$source_prefetch" ]]; then
      cat "/tmp/nix-prefetch-source.err" >&2 || true
      rm -f "/tmp/nix-prefetch-source.err"
      echo "Failed to resolve source hash for $sha" >&2
      continue
    fi
    rm -f "/tmp/nix-prefetch-source.err"

    source_hash=$(printf '%s' "$source_prefetch" | jq -r '.hash // empty')
    if [[ -z "$source_hash" ]]; then
      printf '%s\n' "$source_prefetch" >&2
      echo "Failed to parse source hash for $sha" >&2
      continue
    fi

    source_store_path=$(printf '%s' "$source_prefetch" | jq -r '.path // .storePath // empty')
    if [[ -z "$source_store_path" ]]; then
      echo "Failed to parse source store path for $sha" >&2
      continue
    fi

    log "Source hash: $source_hash"

    perl -0pi -e "s|rev = \"[^\"]+\";|rev = \"${sha}\";|" "$source_file"
    perl -0pi -e "s|hash = \"[^\"]+\";|hash = \"${source_hash}\";|" "$source_file"
    # Force a fresh pnpmDepsHash recalculation for the candidate rev.
    perl -0pi -e "s|pnpmDepsHash = \"[^\"]*\";|pnpmDepsHash = \"\";|" "$source_file"

    if ! build_with_hash_refresh "checks.x86_64-linux.source-smoke" "source smoke to validate pnpmDepsHash"; then
      continue
    fi

    if ! build_with_hash_refresh "openclaw-gateway" "gateway package"; then
      continue
    fi
    selected_sha="$sha"
    selected_hash="$source_hash"
    selected_source_store_path="$source_store_path"
    selected_source_url="$source_url"
    break
  done

  if [[ -z "$selected_sha" ]]; then
    echo "No buildable upstream openclaw revision found; skipping openclaw bump." >&2
    exit 1
  fi
  log "Selected upstream SHA: $selected_sha"

  log "Fetching latest release metadata"
  release_json=$(gh api /repos/openclaw/openclaw/releases?per_page=20 || true)
  if [[ -z "$release_json" ]]; then
    echo "Failed to fetch release metadata" >&2
    exit 1
  fi

  release_tag=$(printf '%s' "$release_json" | jq -r '[.[] | select([.assets[]?.name | (test("^OpenClaw-.*\\.zip$") and (test("dSYM") | not))] | any)][0].tag_name // empty')
  if [[ -z "$release_tag" ]]; then
    echo "Failed to resolve a release tag with an OpenClaw app asset" >&2
    exit 1
  fi
  log "Latest app release tag with asset: $release_tag"

  app_url=$(printf '%s' "$release_json" | jq -r '[.[] | select([.assets[]?.name | (test("^OpenClaw-.*\\.zip$") and (test("dSYM") | not))] | any)][0].assets[] | select(.name | (test("^OpenClaw-.*\\.zip$") and (test("dSYM") | not))) | .browser_download_url' | head -n 1 || true)
  if [[ -z "$app_url" ]]; then
    echo "Failed to resolve OpenClaw app asset URL from latest release" >&2
    exit 1
  fi
  log "App asset URL: $app_url"

  app_prefetch=$(
    nix --extra-experimental-features "nix-command flakes" store prefetch-file --unpack --json "$app_url" 2>"/tmp/nix-prefetch-app.err" \
      || true
  )
  if [[ -z "$app_prefetch" ]]; then
    cat "/tmp/nix-prefetch-app.err" >&2 || true
    rm -f "/tmp/nix-prefetch-app.err"
    echo "Failed to resolve app hash" >&2
    exit 1
  fi
  rm -f "/tmp/nix-prefetch-app.err"

  app_hash=$(printf '%s' "$app_prefetch" | jq -r '.hash // empty')
  if [[ -z "$app_hash" ]]; then
    printf '%s\n' "$app_prefetch" >&2
    echo "Failed to parse app hash" >&2
    exit 1
  fi
  log "App hash: $app_hash"

  app_version="${release_tag#v}"
  perl -0pi -e "s|version = \"[^\"]+\";|version = \"${app_version}\";|" "$app_file"
  perl -0pi -e "s|url = \"[^\"]+\";|url = \"${app_url}\";|" "$app_file"
  perl -0pi -e "s|hash = \"[^\"]+\";|hash = \"${app_hash}\";|" "$app_file"

  if [[ -z "$selected_source_store_path" ]]; then
    echo "Missing source path for selected upstream revision" >&2
    exit 1
  fi

  log "Regenerating openclaw config options from upstream schema"
  tmp_src=$(mktemp -d)
  cleanup_tmp() {
    rm -rf "$tmp_src"
  }
  trap cleanup_tmp EXIT

  if [[ -d "$selected_source_store_path" ]]; then
    cp -R "$selected_source_store_path" "$tmp_src/src"
  elif [[ -f "$selected_source_store_path" ]]; then
    mkdir -p "$tmp_src/src"
    tar -xf "$selected_source_store_path" -C "$tmp_src/src" --strip-components=1
  else
    echo "Source path not found: $selected_source_store_path" >&2
    exit 1
  fi
  chmod -R u+w "$tmp_src/src"

  nix shell --extra-experimental-features "nix-command flakes" nixpkgs#nodejs_22 nixpkgs#pnpm_10 -c \
    bash -c "cd '$tmp_src/src' && pnpm install --frozen-lockfile --ignore-scripts"

  nix shell --extra-experimental-features "nix-command flakes" nixpkgs#nodejs_22 nixpkgs#pnpm_10 -c \
    bash -c "cd '$tmp_src/src' && OPENCLAW_SCHEMA_REV='${selected_sha}' pnpm exec tsx '$repo_root/nix/scripts/generate-config-options.ts' --repo . --out '$config_options_file'"

  cleanup_tmp
  trap - EXIT

  log "Building app to validate fetchzip hash"
  current_system=$(nix eval --impure --raw --expr 'builtins.currentSystem' 2>/dev/null || true)
  if [[ "$current_system" == *darwin* ]]; then
    app_build_log=$(mktemp)
    if ! nix build .#openclaw-app --accept-flake-config >"$app_build_log" 2>&1; then
      app_hash_mismatch=$(grep -Eo 'got: *sha256-[A-Za-z0-9+/=]+' "$app_build_log" | head -n 1 | sed 's/.*got: *//' || true)
      if [[ -n "$app_hash_mismatch" ]]; then
        log "App hash mismatch detected: $app_hash_mismatch"
        perl -0pi -e "s|hash = \"[^\"]+\";|hash = \"${app_hash_mismatch}\";|" "$app_file"
        if ! nix build .#openclaw-app --accept-flake-config >"$app_build_log" 2>&1; then
          tail -n 200 "$app_build_log" >&2 || true
          rm -f "$app_build_log"
          exit 1
        fi
      else
        tail -n 200 "$app_build_log" >&2 || true
        rm -f "$app_build_log"
        exit 1
      fi
    fi
    rm -f "$app_build_log"
  else
    log "Skipping app build on non-darwin system (${current_system:-unknown})"
  fi

  exit 0
); then
  log "Openclaw bump succeeded"
else
  openclaw_bump_failed=1
  log "Openclaw bump skipped/failed; restoring openclaw pin files"
  cp "$openclaw_backup_dir/$(basename "$source_file")" "$source_file"
  cp "$openclaw_backup_dir/$(basename "$app_file")" "$app_file"
  if [[ -f "$openclaw_backup_dir/$(basename "$config_options_file")" ]]; then
    cp "$openclaw_backup_dir/$(basename "$config_options_file")" "$config_options_file"
  fi
fi

# NOTE: /tmp is ephemeral in GitHub Actions; keep cleanup best-effort.
rm -rf "$openclaw_backup_dir" 2>/dev/null || true

if [[ "$openclaw_bump_failed" -eq 1 ]]; then
  current_rev=$(awk -F'"' '/rev =/{print $2}' "$source_file" | head -n 1)
  if [[ -n "$upstream_main_sha" && -n "$current_rev" && "$current_rev" != "$upstream_main_sha" ]]; then
    echo "Openclaw bump failed while upstream advanced (${current_rev} -> ${upstream_main_sha}); failing run." >&2
    exit 1
  fi
fi

if git diff --quiet; then
  echo "No pin changes detected."
  exit 0
fi

tools_changed=0
openclaw_changed=0

if ! git diff --quiet -- "$flake_lock_file"; then
  tools_changed=1
fi

if ! git diff --quiet -- "$source_file" "$app_file" "$config_options_file"; then
  openclaw_changed=1
fi

subject="🤖 codex: bump pins"
if [[ "$tools_changed" -eq 1 && "$openclaw_changed" -eq 1 ]]; then
  subject="🤖 codex: bump pins (tools + openclaw)"
elif [[ "$tools_changed" -eq 1 ]]; then
  subject="🤖 codex: bump nix-steipete-tools"
elif [[ "$openclaw_changed" -eq 1 ]]; then
  subject="🤖 codex: bump openclaw pins"
fi

log "Committing updated pins"
git add "$flake_lock_file" "$source_file" "$app_file" "$config_options_file"
git commit -F - <<EOF
${subject}

What:
- update pinned inputs/pkgs for nix-openclaw (best-effort)

Why:
- keep the flake fresh automatically

Tests:
- nix build .#openclaw-gateway --accept-flake-config
- nix build .#openclaw-app --accept-flake-config (darwin only)
EOF

log "Rebasing on latest main"
git fetch origin main
git rebase origin/main

git push origin HEAD:main
