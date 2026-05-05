#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir="$repo_root/nix/tests/hm-activation-macos"
home_dir="/tmp/hm-activation-home"
label="com.steipete.openclaw.gateway.hm-test"
plist="$home_dir/Library/LaunchAgents/$label.plist"

cleanup() {
  if command -v launchctl >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$label" >/dev/null 2>&1 || true
    if [ -e "$plist" ]; then
      launchctl bootout "gui/$UID" "$plist" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

rm -rf "$home_dir"
mkdir -p "$home_dir"
cleanup

export HOME="$home_dir"
export USER="runner"
export LOGNAME="$USER"

cd "$test_dir"

nix build --accept-flake-config --impure \
  --override-input nix-openclaw "path:$repo_root" \
  .#homeConfigurations.hm-test.activationPackage

./result/activate

test -f "$HOME/.openclaw/openclaw.json"
test -f "$plist"

if command -v launchctl >/dev/null 2>&1; then
  state_file="$home_dir/launchd-state.txt"
  running=false
  for _ in {1..20}; do
    if launchctl print "gui/$UID/$label" >"$state_file" 2>&1 && grep -q "state = running" "$state_file"; then
      running=true
      break
    fi
    sleep 0.5
  done
  if [ "$running" != true ]; then
    cat "$state_file" >&2
    exit 1
  fi

  openclaw_bin=$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$plist")
  health_file="$home_dir/gateway-health.json"
  healthy=false
  for _ in {1..30}; do
    if "$openclaw_bin" gateway health \
      --url "ws://127.0.0.1:18999" \
      --token "hm-activation-test-token" \
      --json \
      --timeout 3000 >"$health_file" 2>&1 \
      && grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$health_file"; then
      healthy=true
      break
    fi
    sleep 0.5
  done
  if [ "$healthy" != true ]; then
    cat "$health_file" >&2
    exit 1
  fi
fi
