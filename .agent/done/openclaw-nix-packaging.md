# Stabilize OpenClaw Nix Packaging Around Runnable Capabilities

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document follows `.agent/PLANS.md` in this repository.

## Purpose / Big Picture

The goal is to make `openclaw/nix-openclaw` a reliable Nix packaging surface for OpenClaw users on Linux and macOS. A user should be able to install OpenClaw from this flake, build it with Nix, and run the gateway on Linux or macOS. On macOS, the flake should also provide the desktop `.app` when upstream has published a usable desktop artifact for the same OpenClaw release.

The current system is too brittle because it treats "latest stable GitHub release has a file named `OpenClaw-*.zip`" as the release contract. Upstream release flow does not work that way: OpenClaw source tags and GitHub releases can exist before private macOS signing/notarization workflows upload `.zip`, `.dmg`, and `.dSYM.zip` assets. Missing desktop assets are a release-publication state, not proof that the source gateway cannot be packaged.

After this work, the user-facing package boundary should be simple: users install `openclaw`. The `openclaw` output is the batteries-included bundle: gateway plus tools on Linux, and gateway plus tools plus the macOS app on Darwin. The `openclaw-gateway`, `openclaw-tools`, and `openclaw-app` outputs remain as component outputs for Nix modules, checks, and debugging, but they are not separate product tracks. The update automation should pick the newest fully packageable stable release for default promotion, while separately reporting newer source-only releases that are not yet full desktop releases.

## Progress

- [x] (2026-05-04 17:02Z) Assessed current repository state: `openclaw/nix-openclaw` is pinned to OpenClaw `v2026.4.14`; hourly yolo has failed since mid-April; latest upstream stable releases `v2026.5.3` and `v2026.5.3-1` currently have no public app assets; latest stable with public macOS zip asset is `v2026.5.2`.
- [x] (2026-05-04 17:02Z) Read OpenClaw public release workflows and maintainer release docs in `/Users/josh/code/research/openclaw` and `/Users/josh/code/research/maintainers`.
- [x] (2026-05-04 17:02Z) Determined DJTBOT deployment freshness is out of scope for this plan; this plan focuses only on public Nix packaging.
- [x] (2026-05-04 17:42Z) Read the current global agent guidance in `/Users/josh/.codex/AGENTS.md`, `/Users/josh/code/nix/AGENTS.md`, and `/Users/josh/code/nix/ai-stack/AGENTS.md`; refined this plan around one obvious path, no speculative fallbacks, and existing repo seams.
- [x] (2026-05-04 17:42Z) Re-checked the package graph and upstream gateway CLI. Confirmed `openclaw` is already the default package, `openclaw-gateway` is the source-built CLI component, and runtime smoke should use WebSocket gateway health rather than HTTP `/health`.
- [x] (2026-05-04 17:55Z) Captured Josh's README direction: onboarding should be agent-first, where the user tells a coding agent they want OpenClaw using Nix and the agent interviews/configures/verifies.
- [x] (2026-05-04 19:49Z) Updated README package language so `openclaw` is the single canonical install target, the primary setup flow is agent-first, and component outputs are documented as advanced/internal build seams.
- [x] (2026-05-04 19:49Z) Implemented release discovery that understands package capabilities instead of failing on the first assetless stable release.
- [x] (2026-05-04 19:49Z) Fixed app artifact hashing/unpacking so Nix computes the exact `fetchzip` hash from real unpacked contents and aborts clearly if no `.app` is present.
- [x] (2026-05-04 19:49Z) Repaired config validation so it uses packaged public CLI behavior instead of scanning bundled `dist/config-*.js` internals.
- [x] (2026-05-04 19:49Z) Added runtime smoke checks that prove the Nix-built gateway starts and answers a local health/RPC probe on Linux and macOS.
- [x] (2026-05-04 19:49Z) Updated CI/yolo promotion to validate and promote the newest full packageable stable release, with source-only newer releases reported but not promoted into the default bundle.
- [x] (2026-05-04 19:49Z) Updated README packaging docs after behavior changes were implemented and verified.
- [x] (2026-05-04 19:49Z) Fixed the local Linux external-builder failure by moving the OpenClaw build working tree and PNPM store onto the Nix output filesystem during builds, then cleaning that scratch before outputs finish.
- [x] (2026-05-04 19:49Z) Verified final gates: selector fixture, updater syntax, workflow YAML parse, live selector no-op, `nix flake show`, full Linux CI, and full Darwin CI.
- [x] (2026-05-05 06:45Z) Created daily Codex maintainer automation `nix-openclaw-maintainer` for early Amsterdam mornings; documented that it is an agentic repair run, not a competing release pipeline.
- [x] (2026-05-05 06:45Z) Ran a fresh self-review pass and tightened noisy Home Manager VM diagnostics by removing a space-containing `NODE_OPTIONS` systemd assignment.
- [x] (2026-05-05 06:45Z) Fixed a self-review finding in yolo promotion: validation jobs now record the materialized release diff digest, and promotion refuses to push if it re-materializes a different diff.
- [x] (2026-05-05 06:45Z) Removed the dead standalone config-options check file and renamed the combined gateway/config-options derivation to `openclaw-source-checks.nix`.

## Surprises & Discoveries

- Observation: OpenClaw's public `macos-release.yml` workflow is validation-only.
  Evidence: `openclaw/openclaw/.github/workflows/macos-release.yml` says it validates the public release handoff and does not sign, notarize, or upload macOS assets.

- Observation: Real macOS release assets are produced by private workflows after the public GitHub release exists.
  Evidence: `/Users/josh/code/research/maintainers/release/macos.md` says `openclaw/releases-private/.github/workflows/openclaw-macos-publish.yml` uploads `OpenClaw-<version>.zip`, `OpenClaw-<version>.dmg`, and `OpenClaw-<version>.dSYM.zip` to the existing public GitHub release.

- Observation: Recent stable OpenClaw releases are not all full desktop releases at the time yolo sees them.
  Evidence: `gh api '/repos/openclaw/openclaw/releases?per_page=30'` showed `v2026.5.3-1`, `v2026.5.3`, `v2026.4.23`, and `v2026.4.21` as stable releases with no assets, while nearby stable releases such as `v2026.5.2`, `v2026.4.29`, and `v2026.4.27` had `.zip`, `.dmg`, and `.dSYM.zip`.

- Observation: The current app hash helper is wrong for current Nix behavior.
  Evidence: yolo logs show `nix-prefetch-url` prints a real `/nix/store/...-OpenClaw-<version>.zip` path, but `scripts/update-pins.sh` treats the final hash line as a path component and synthesizes a different non-existent store path before calling `unzip`.

- Observation: Building the macOS `.app` from source inside this flake is not the right first move.
  Evidence: upstream `scripts/package-mac-app.sh` depends on SwiftPM, Xcode 26.1, Sparkle, Developer ID signing, notarization-adjacent packaging, MLX TTS helper builds, Control UI assets, and private release workflows. The Nix flake already has a clean boundary for the desktop app: use the published app bundle artifact on Darwin.

- Observation: At planning time, the checked upstream OpenClaw source did not expose `openclaw config validate --json`.
  Evidence: `/Users/josh/code/research/openclaw/src/cli/config-cli.ts` registers `config get`, `config set`, and `config unset`, but no `config validate`. `config get` calls `loadValidConfig()`, so `openclaw config get gateway --json` is the current public CLI path that proves the generated config can be loaded and validated.

- Observation: The selected packageable release `v2026.5.2` does expose `openclaw config validate --json`.
  Evidence: `nix/scripts/check-config-validity.mjs` now runs the packaged CLI's `config validate --json` and then checks `config get agents.defaults.workspace --json` against the generated Home Manager config.

- Observation: Gateway liveness must be proved through WebSocket RPC, not HTTP.
  Evidence: upstream registers `openclaw gateway health` and `openclaw gateway call health`, both backed by the gateway `health` RPC method. The main HTTP dispatcher has no stable `/health` route, and unmatched HTTP paths return 404.

- Observation: Determinate's local Linux external builder exposes only about 3.9 GiB for `/build`, while the OpenClaw PNPM store tar expands to about 7.8 GiB.
  Evidence: a tiny `x86_64-linux` derivation reported `/build` on a 3.9 GiB tmpfs, and `pnpm-store.tar.zst` contains 61,553 tar entries totaling about 7.80 GiB. The first Linux gateway build failed at PNPM-store extraction with `No space left on device`.

- Observation: The Nix-built gateway hit an upstream runtime guard that rejected Nix-store hardlinks in bundled plugin public surface files.
  Evidence: a runtime smoke attempt failed opening `anthropic/provider-policy-api.js` because `openBoundaryFileSync` rejected files with link count greater than one. Nix store deduplication can hardlink immutable package files, so the patch now allows hardlinks only under `OPENCLAW_PACKAGE_ROOT`.

## Decision Log

- Decision: Keep one public default package line based on the newest fully packageable stable release, not the newest source tag when desktop assets are missing.
  Rationale: The README promises "Gateway + tools everywhere; macOS app on macOS." Promoting a source-only release would either drop the macOS app from the default Darwin bundle or create a source/app version mismatch. Both are worse for users than staying on the latest complete release while reporting newer incomplete releases.
  Date/Author: 2026-05-04 / Codex

- Decision: Do not split the repository into separate "desktop" and "server" release tracks.
  Rationale: The package outputs should be segmented, not the product mental model. `openclaw-gateway` is the headless/server-capable source build, `openclaw-app` is Darwin-only desktop, and `openclaw` combines the appropriate outputs for the platform. Callers should not need to know upstream release timing details.
  Date/Author: 2026-05-04 / Codex

- Decision: Treat the upstream macOS zip as the preferred desktop app artifact, but validate artifact contents instead of trusting only the filename.
  Rationale: Maintainer docs define the real publish outputs as `.zip`, `.dmg`, and `.dSYM.zip`. The Sparkle zip is the most Nix-friendly app-bundle source. The robust boundary is to pick a plausible desktop artifact and verify it actually unpacks to an `.app`; filename matching alone is not enough.
  Date/Author: 2026-05-04 / Codex

- Decision: Add runtime smoke checks before changing deployment users such as DJTBOT.
  Rationale: The user's goal is public package health. Deployment freshness is downstream of packaging correctness and is intentionally out of scope for this plan.
  Date/Author: 2026-05-04 / Codex

- Decision: Make `openclaw` the only canonical user-facing package name, while keeping `openclaw-gateway`, `openclaw-tools`, and `openclaw-app` as component outputs.
  Rationale: Josh wants one thing to install, and the README already promises "One flake, everything works." Removing component outputs would make CI, Home Manager module wiring, macOS app packaging, and debugging harder without simplifying the user path. The simpler mental model is: users install `openclaw`; maintainers may inspect component outputs when diagnosing packaging.
  Date/Author: 2026-05-04 / Codex

- Decision: Make the README agent-first.
  Rationale: The intended user is not supposed to become a Nix/OpenClaw packaging expert. The cleanest onboarding is to tell a coding agent "set up OpenClaw with Nix," then let the agent inspect the machine, ask the small number of setup questions, write the local flake, configure secrets, apply Home Manager, and verify the service. Manual commands should remain as reference and recovery material, not the primary story.
  Date/Author: 2026-05-04 / Josh/Codex

- Decision: Use output-backed scratch for OpenClaw Node builds.
  Rationale: The package must build on the local Linux external builder and in CI without assuming a large `/build` filesystem. Moving the build root and PNPM store under `$out` during the build uses the Nix store filesystem, then the scripts remove `.pnpm-store` and `.openclaw-build` before the output is finalized.
  Date/Author: 2026-05-04 / Codex

- Decision: Make the Nix gateway Vitest runner resource-bounded but not fragile.
  Rationale: The one-CPU Linux builder timed out and then hit JS heap OOM with upstream's full gateway suite. The Nix check now defaults to one worker, fork pool, a 60s per-test timeout, and a 4 GiB Node heap so constrained builders fail real hangs without failing normal slow tests.
  Date/Author: 2026-05-04 / Codex

- Decision: Use the daily Codex automation as an agentic maintainer repair loop, not as another updater.
  Rationale: Yolo is already the release updater. The daily run should check whether yolo and CI can still uphold the package contract, then fix nix-openclaw itself when the breakage is in this repo. It may commit and push directly to `main` only after self-review and full gates pass.
  Date/Author: 2026-05-05 / Josh/Codex

## Outcomes & Retrospective

Implemented. The repo now promotes the newest stable release that satisfies the public Nix package contract, not blindly the newest stable source tag. As of 2026-05-04, that is `v2026.5.2`; `v2026.5.3-1` and `v2026.5.3` are reported as skipped because they do not publish the required public macOS zip asset.

The work also found and fixed two packaging bugs that were not obvious from release selection alone: Nix-store hardlinks tripped OpenClaw's bundled plugin public-surface guard, and the local Linux external builder could not fit the PNPM store in `/build`. Both are now handled in the Nix-owned packaging layer.

Final local verification passed:

    node scripts/select-openclaw-release.test.mjs
    bash -n scripts/update-pins.sh
    ruby -e 'require "yaml"; YAML.load_file(".github/workflows/yolo-update.yml")'
    GITHUB_ACTIONS=true scripts/update-pins.sh select
    nix flake show --accept-flake-config
    nix build .#checks.x86_64-linux.ci --accept-flake-config --max-jobs 1
    nix build .#checks.aarch64-darwin.ci --accept-flake-config --max-jobs 1

## Context and Orientation

This repository packages OpenClaw with Nix. OpenClaw is a fast-moving application with a TypeScript/Node gateway, bundled plugins, a Control UI, and a native macOS desktop companion app. A gateway is a long-running process that receives messages and tool calls; in this repo it is built as `openclaw-gateway`. The desktop app is a macOS `.app` bundle; in this repo it is `openclaw-app` and exists only on Darwin systems.

The important current files are:

- `flake.nix`: exposes packages, apps, checks, and modules for `x86_64-linux` and `aarch64-darwin`.
- `nix/packages/default.nix`: constructs the package set. Today it already makes `openclaw-gateway` everywhere, `openclaw-app` only on Darwin, and `openclaw` as the bundle.
- `nix/packages/openclaw-gateway.nix`: builds the source gateway from the upstream OpenClaw source pin in `nix/sources/openclaw-source.nix`.
- `nix/packages/openclaw-app.nix`: fetches a published upstream macOS `.zip` and installs the contained `.app`.
- `nix/packages/openclaw-batteries.nix`: combines gateway, app when present, and tools into the default batteries-included bundle.
- `scripts/update-pins.sh`: current update boundary. It selects one upstream release, computes source and app hashes, rewrites pin files, refreshes `pnpmDepsHash`, and regenerates Nix config options.
- `.github/workflows/yolo-update.yml`: hourly automation that calls `scripts/update-pins.sh`, validates on Linux and macOS, and promotes to `main` only after both pass.
- `nix/checks/openclaw-config-validity.nix` and `nix/scripts/check-config-validity.mjs`: validate a generated Home Manager config against the packaged OpenClaw validator. This currently scans internal bundle files and breaks when upstream bundling changes.
- `nix/checks/openclaw-package-contents.nix` and `nix/scripts/check-package-contents.sh`: assert required runtime files exist in the built gateway output.
- `nix/checks/openclaw-source-checks.nix`: runs upstream gateway Vitest tests and verifies generated config options inside one shared source build.

The upstream release flow matters. `openclaw/openclaw` remains the source of truth for source, tags, GitHub releases, npm publish, and the public `appcast.xml`. The public `macos-release.yml` workflow validates release handoff only. Private workflows in `openclaw/releases-private` perform macOS validation, signing, notarization, packaging, and real publish. A stable GitHub release can therefore exist before `.zip`, `.dmg`, and `.dSYM.zip` are uploaded.

This current complexity is paid by maintainers and future agents. They must know GitHub release timing, private macOS publish behavior, Nix `fetchzip` hash semantics, TypeScript bundle internals, and yolo workflow sequencing. The plan reduces that burden by putting release capability policy behind one release-discovery boundary and putting runtime proof into Nix checks.

## Milestones

Milestone 1 is the product contract and onboarding cleanup. At the end of this milestone, README and AGENTS language should say one simple thing: users ask their coding agent to set up `openclaw` with Nix. The README should give the agent a high-quality prompt and say that the agent should inspect the machine, interview the user for missing choices, create the local flake, wire secrets, apply Home Manager, and verify the service. The component outputs still exist because the repository needs them, but they are documented as advanced build seams rather than separate products. This milestone has no behavior change. Its proof is a short README diff plus `nix flake show --accept-flake-config` showing `packages.<system>.default` and `packages.<system>.openclaw` point at the same user-facing bundle.

Milestone 2 is release selection. At the end of this milestone, `scripts/update-pins.sh select` should no longer fail merely because the newest stable release lacks a macOS app asset. It should select the newest stable release that satisfies the full Nix package contract and report skipped newer stable releases. This milestone is pure policy logic and should be tested with a local fixture before it touches GitHub or Nix builds. Its proof is a fixture test where `v2026.5.3-1` and `v2026.5.3` are skipped and `v2026.5.2` is selected, plus a live `GITHUB_ACTIONS=true scripts/update-pins.sh select` run that prints the selected tuple.

Milestone 3 is pin materialization. At the end of this milestone, `scripts/update-pins.sh apply <tag> <sha> <app-url>` should correctly update the source pin, app pin, `pnpmDepsHash`, and generated config options for the selected release. The app hash logic must use the actual prefetched archive path, unpack it, verify an `.app` exists, and compute the hash from the unpacked directory. Its proof is an apply run for the selected release, a Darwin `nix build .#openclaw-app --accept-flake-config -L` that yields `Applications/OpenClaw.app`, and a gateway build that succeeds after `pnpmDepsHash` refresh.

Milestone 4 is public config validation. At the end of this milestone, the config-validity check should stop importing private bundled files from `dist/`. It should execute the packaged CLI against the generated config. Because current upstream has no `config validate` command, use the existing public validation path: `openclaw config get gateway --json` with `OPENCLAW_CONFIG_PATH` pointing at the generated config. Its proof is `nix build .#checks.<system>.config-validity --accept-flake-config -L` on Linux and Darwin.

Milestone 5 is runtime proof. At the end of this milestone, CI should prove that the Nix-built gateway can start and answer a WebSocket health RPC without provider secrets. The smoke check should start the gateway on loopback with an ephemeral port and a generated token, then call `openclaw gateway health --url ws://127.0.0.1:<port> --token <token> --json --timeout 10000` and assert `ok: true`. Its proof is `nix build .#checks.<system>.gateway-smoke --accept-flake-config -L` on Linux and Darwin.

Milestone 6 is automation and documentation. At the end of this milestone, yolo should use the same selection and materialization boundaries, validate Linux and macOS, summarize skipped newer stable releases, and promote only after the package contract passes. README should describe the actual behavior: latest full packageable stable release, not blindly latest GitHub stable tag. Its proof is a full Linux CI aggregator, a full Darwin CI aggregator plus macOS Home Manager activation, and a manual yolo run that either promotes the selected release or exits as a clean no-op.

## Plan of Work

First, clean up the product language without changing package behavior. Update `README.md` and this repository's `AGENTS.md` so `openclaw` is the canonical user-facing package. Make README onboarding agent-first: the primary call to action is to ask a coding agent to set up OpenClaw with Nix, and the agent's job is to inspect the user's platform, ask for any missing setup choices, write the local flake from this repo's template, wire secrets, apply Home Manager, and verify the service. Keep `openclaw-gateway`, `openclaw-tools`, and `openclaw-app` exposed because existing Nix modules, checks, and advanced users need component outputs, but do not present them as competing install paths.

Next, replace the update policy with capability-aware release discovery. Add a small repo script, for example `scripts/select-openclaw-release.mjs`, that accepts the JSON returned by `gh api /repos/openclaw/openclaw/releases?per_page=100` and returns a structured selection. It should identify:

- `latestStable`: the newest non-draft, non-prerelease release, whether or not it has assets.
- `latestFullPackageableStable`: the newest stable release whose tag resolves to a source SHA and whose assets include a desktop artifact that can be used for `openclaw-app`.
- `skippedStableReleases`: newer stable releases skipped because they are missing desktop artifacts.

The desktop artifact selector should require a non-dSYM zip whose asset unpacks to an `.app`. Do not add DMG fallback support in this plan. Upstream's real publish path is documented to upload the zip, and treating a missing zip as "not full desktop-packageable yet" keeps the policy simple. The caller should validate content during `apply`, not only during `select`.

Then change `scripts/update-pins.sh` so `select` emits the newest full packageable stable release, plus a clear diagnostic summary for skipped newer releases. Keep `apply <tag> <sha> <app-url>` as the materialization command for now. This preserves the existing workflow interface while hiding release-policy details inside selection.

Next, fix app artifact hashing. Replace `unpacked_zip_hash()` with logic that uses the actual path returned by a Nix prefetch command, unpacks into a temp directory, verifies that exactly one usable `.app` is present within a shallow depth, and computes the hash from the unpacked directory in the same shape expected by `fetchzip { stripRoot = false; }`. Any unzip or `.app` discovery failure must abort the script. Do not synthesize `/nix/store` paths from hashes.

Next, repair config validation. Prefer running packaged CLI behavior over importing private bundle internals. Current upstream has no `openclaw config validate` command, so use `config get` as the public validation path. The Nix check should set `OPENCLAW_CONFIG_PATH` to the generated config file and run:

    $OPENCLAW_GATEWAY/bin/openclaw config get gateway --json

This command calls the same config loader and validator users exercise through the CLI. If it requires extra environment to avoid touching real user state, set `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `OPENCLAW_STATE_DIR`, and `OPENCLAW_LOG_DIR` to fresh temp directories inside the check. Do not keep the old importer as a fallback; it is the fragile behavior this milestone removes.

Next, add a runtime smoke check. Create a Nix check such as `nix/checks/openclaw-gateway-smoke.nix` backed by a real script under `nix/scripts/`, for example `nix/scripts/gateway-smoke.mjs` or `nix/scripts/gateway-smoke.sh`. The check should:

1. Create isolated temp `HOME`, `XDG_*`, `OPENCLAW_STATE_DIR`, and `OPENCLAW_LOG_DIR` directories.
2. Run `$OPENCLAW_GATEWAY/bin/openclaw --version` and verify it prints a non-empty version.
3. Start `$OPENCLAW_GATEWAY/bin/openclaw gateway run --port <free-port> --bind loopback --allow-unconfigured --auth token --token <generated-token>` in the foreground.
4. Poll `$OPENCLAW_GATEWAY/bin/openclaw gateway health --url ws://127.0.0.1:<free-port> --token <generated-token> --json --timeout 10000` until it returns JSON with `ok: true`.
5. Terminate the gateway process and fail if startup, health, or shutdown fails.

Use WebSocket RPC, not HTTP `/health`, because current upstream does not expose a stable HTTP health route. Use a token even on loopback because the CLI requires explicit credentials when `--url` overrides the config-derived gateway URL. Do not use real provider secrets and do not contact external services.

Then wire checks into `flake.nix`. The CI aggregator should include the new smoke check on both Linux and Darwin. Keep existing package contents, config validity, gateway tests, Home Manager activation, and app build checks, but classify failures by capability in logs so a future automation can explain what failed.

Finally, update `.github/workflows/yolo-update.yml` and docs. The workflow should no longer fail solely because the latest stable release lacks app assets. It should promote the newest full packageable stable release after Linux and macOS checks pass. Its summary should mention any newer skipped source-only stable releases so maintainers can see whether upstream mac publishing is lagging. README packaging docs should say that the flake tracks the newest stable release that can satisfy the public Nix package contract: gateway builds on Linux/macOS and macOS app is available on Darwin.

## Concrete Steps

Work from the repository root:

    cd /Users/josh/code/nix-openclaw

Before editing, check the current worktree:

    git status --short

Clean up product naming first. Update README so the first setup path is agent-first: "tell your coding agent you want OpenClaw using Nix." Keep the existing prompt block, but make it the primary onboarding flow and make clear that the agent should interview the user for OS, CPU, Home Manager target, channels, documents, and secrets. Also make `.#openclaw` the one recommended package. Keep the package table, but label `openclaw-gateway`, `openclaw-tools`, and `openclaw-app` as advanced component outputs. Verify the exposed outputs:

    nix flake show --accept-flake-config

Expected result:

    packages.<system>.default and packages.<system>.openclaw are present.
    openclaw-gateway remains present for checks/modules/debugging.

Implement release selection with fixtures. Add a pure selector script and unit fixture coverage. The selector must be runnable without network access when passed a local release JSON fixture, so it can be tested cheaply. A successful fixture test should prove that when releases are ordered as `v2026.5.3-1` with no assets, `v2026.5.3` with no assets, and `v2026.5.2` with `OpenClaw-2026.5.2.zip`, selection chooses `v2026.5.2` and reports the two newer skipped tags.

Run:

    node scripts/select-openclaw-release.test.mjs

Expected result:

    release selection: ok

Fix `scripts/update-pins.sh` and verify syntax:

    bash -n scripts/update-pins.sh

Run release selection in GitHub Actions mode without applying:

    GITHUB_ACTIONS=true scripts/update-pins.sh select

Expected result on 2026-05-04, unless upstream assets changed:

    release_tag=v2026.5.2
    release_sha=8b2a6e57fef6c582ec6d27b85150616f9e3a7ba4
    app_url=https://github.com/openclaw/openclaw/releases/download/v2026.5.2/OpenClaw-2026.5.2.zip
    release_version=2026.5.2

Fix app hash materialization. Validate it by applying the selected release in a disposable worktree or on the working branch, then building `openclaw-app` on Darwin:

    GITHUB_ACTIONS=true scripts/update-pins.sh apply v2026.5.2 8b2a6e57fef6c582ec6d27b85150616f9e3a7ba4 https://github.com/openclaw/openclaw/releases/download/v2026.5.2/OpenClaw-2026.5.2.zip
    nix build .#openclaw-app --accept-flake-config -L

Expected result:

    The build succeeds and the result contains Applications/OpenClaw.app.

Repair config validation by changing `nix/scripts/check-config-validity.mjs` so it executes the packaged CLI:

    $OPENCLAW_GATEWAY/bin/openclaw config get gateway --json

Keep `OPENCLAW_CONFIG_PATH` pointed at the generated config file. Run:

    nix build .#checks.x86_64-linux.config-validity --accept-flake-config -L
    nix build .#checks.aarch64-darwin.config-validity --accept-flake-config -L

Add the gateway smoke check. It should start the packaged gateway with loopback bind and a generated token, then prove the WebSocket health RPC:

    $OPENCLAW_GATEWAY/bin/openclaw gateway run --allow-unconfigured --bind loopback --port <port> --auth token --token <token>
    $OPENCLAW_GATEWAY/bin/openclaw gateway health --url ws://127.0.0.1:<port> --token <token> --json --timeout 10000

Run:

    nix build .#checks.x86_64-linux.gateway-smoke --accept-flake-config -L
    nix build .#checks.aarch64-darwin.gateway-smoke --accept-flake-config -L

Run full CI aggregators:

    nix build .#checks.x86_64-linux.ci --accept-flake-config -L
    nix build .#checks.aarch64-darwin.ci --accept-flake-config -L

If local Darwin or Linux hardware is not available, push a branch and use GitHub Actions for the missing platform. Do not claim platform success until the corresponding check has actually run.

## Validation and Acceptance

Acceptance is user-visible package behavior, not just a green script.

The release selector is accepted when it chooses the newest stable release that satisfies the full Nix package contract, and reports newer stable releases that were skipped because desktop assets are not yet published.

The app package is accepted when `nix build .#openclaw-app --accept-flake-config -L` succeeds on Darwin and the result contains `Applications/OpenClaw.app`.

The gateway package is accepted when `nix build .#openclaw-gateway --accept-flake-config -L` succeeds on Linux and Darwin, and the gateway smoke check proves `openclaw --version` and local gateway health both work from the Nix-built output.

The automation is accepted when a yolo run can select, materialize, validate, and promote the latest full packageable stable release without being blocked by newer stable releases that lack public macOS assets.

The docs are accepted when `AGENTS.md` and `README.md` no longer say the newest stable missing a macOS zip is by itself a yolo failure. They should instead state the actual contract: users ask a coding agent to set up `openclaw`, and automation promotes the newest stable release that builds and runs under the Nix package outputs.

## Idempotence and Recovery

`scripts/update-pins.sh select` must be read-only. `apply` may rewrite `nix/sources/openclaw-source.nix`, `nix/packages/openclaw-app.nix`, and `nix/generated/openclaw-config-options.nix`, but it must restore those files if materialization fails before success.

When changing yolo or pin behavior, never overwrite tracked upstream files from outside the repo. If an upstream file is needed for comparison, stage it under `/tmp/` or clone under `/Users/josh/code/research`.

If a candidate release fails source build or runtime smoke, do not paper over the failure by skipping tests or adding broad postpatch hacks. Diagnose whether the failure is an upstream package boundary change, a Nix build dependency issue, or a real runtime regression, and update this plan's `Surprises & Discoveries` and `Decision Log`.

If app assets are missing for the newest stable release, do not fail the whole updater. Select the newest full packageable stable release and include the skipped newer releases in the workflow summary.

## Artifacts and Notes

Current observed release state on 2026-05-04:

    v2026.5.3-1 stable, no assets
    v2026.5.3 stable, no assets
    v2026.5.2 stable, assets: OpenClaw-2026.5.2.dmg, OpenClaw-2026.5.2.dSYM.zip, OpenClaw-2026.5.2.zip
    v2026.4.29 stable, assets: OpenClaw-2026.4.29.dmg, OpenClaw-2026.4.29.dSYM.zip, OpenClaw-2026.4.29.zip

Current `nix-openclaw` pin after implementation:

    OpenClaw source: v2026.5.2, rev 8b2a6e57fef6c582ec6d27b85150616f9e3a7ba4
    macOS app: OpenClaw-2026.5.2.zip
    Top-level Nix bundle: openclaw-2026.5.2

The latest known upstream release gap:

    Latest stable OpenClaw release v2026.5.3-1 is missing the required macOS zip asset

The more important hidden failure mode from earlier yolo apply runs:

    unzip: cannot find or open /nix/store/...-OpenClaw-2026.4.29.zip
    Missing validation module: .../lib/openclaw/dist/config/validation.js

## Interfaces and Dependencies

Keep these interfaces stable unless there is a strong reason to change them:

- `scripts/update-pins.sh select`: prints `key=value` lines for GitHub Actions outputs. It should stay read-only.
- `scripts/update-pins.sh apply <release_tag> <release_sha> <app_url>`: materializes the selected release into repo pin files.
- `nix/sources/openclaw-source.nix`: source pin for the gateway build.
- `nix/packages/openclaw-app.nix`: Darwin-only desktop app artifact pin.
- `.#openclaw`: canonical user-facing package. On Linux it should contain gateway plus tools. On Darwin it should contain gateway plus tools plus `OpenClaw.app`.
- `.#openclaw-gateway`: source-built runnable gateway package.
- `.#openclaw-app`: Darwin-only desktop app package.
- `.#openclaw-tools`: toolchain package used by the batteries-included bundle.

New helper scripts should hide policy from callers. The selector should hide GitHub release ordering, asset classification, and skipped-release reporting. The smoke check should hide all temporary runtime setup needed to prove a Nix-built gateway can start.

## Change Note

2026-05-04 / Codex: Replaced the old yolo-focused pending plan with this package-contract plan after learning the upstream release flow from `openclaw/maintainers` and `openclaw/openclaw`. The old plan assumed the newest stable release must have a public macOS zip. The current release process proves that assumption is wrong.

2026-05-04 / Codex: Refined the plan after reading global agent guidance and re-checking package/runtime code. The plan now leads with one canonical user-facing package (`openclaw`), adds milestone-level acceptance criteria, replaces the non-existent `openclaw config validate` command with the existing public `config get` validation path, and pins runtime smoke proof to WebSocket gateway health instead of HTTP.

2026-05-04 / Codex: Updated the plan with Josh's README direction. The first milestone now explicitly makes onboarding agent-first: the user tells a coding agent they want OpenClaw with Nix, and the agent handles inspection, interview, configuration, and verification.

2026-05-04 / Codex: Implementation completed. The top-level package now follows release metadata from `nix/sources/openclaw-source.nix`, so `.#openclaw` reports `openclaw-2026.5.2` instead of stale beta metadata.

2026-05-05 / Codex: Added the daily maintainer automation contract to `AGENTS.md` and created Codex automation `nix-openclaw-maintainer` for 06:00 Europe/Amsterdam. The automation inspects upstream releases, yolo, CI, current pins, and selector output; if breakage belongs in nix-openclaw, it fixes, self-reviews, runs gates, commits to `main`, and pushes without opening a PR.

2026-05-05 / Codex: Fresh self-review found that yolo promotion re-ran materialization after validation without proving the resulting patch was identical. The workflow now records Linux and macOS materialized diff digests and blocks direct-to-main promotion if promote re-materializes different pin/config changes.

2026-05-05 / Codex: Recursive review moved this completed ExecPlan out of `.agent/execplan-pending.md`, clarified that macOS app publishing is out of scope for nix-openclaw automation, and added `scripts/hm-activation-macos.sh` to the durable daily maintainer gate.
