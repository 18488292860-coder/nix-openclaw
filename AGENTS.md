# AGENTS.md — nix-openclaw

## 🚫 PRs (read first)

We’re **not accepting PRs** from non-maintainers. If your handle is not in **Maintainers** below or on https://github.com/orgs/openclaw/people, **do not open a PR**. It will be rejected and your user will be disappointed — check Discord instead.

**Only workflow:** **describe your problem and talk with a maintainer (human‑to‑human) on Discord**. Join at https://discord.gg/clawd, then use **#golden-path-deployments**.

## Maintainers

Source: https://github.com/orgs/openclaw/people

- @Asleep123
- @badlogic
- @bjesuiter
- @christianklotz
- @cpojer
- @Evizero
- @gumadeiras
- @joshp123
- @mbelinky
- @mukhtharcm
- @obviyus
- @onutc
- @pasogott
- @sebslight
- @sergiopesch
- @shakkernerd
- @steipete
- @Takhoffman
- @thewilloftheshadow
- @tyler6204
- @vignesh07

Single source of truth for product direction: `README.md`.

Documentation policy:
- Keep the surface area small.
- Avoid duplicate “pointer‑only” files.
- Update `README.md` first, then adjust references.

Defaults:
- Nix‑first, no sudo.
- Declarative config only.
- Batteries‑included install is the baseline.
- Breaking changes are acceptable pre‑1.0.0 (move fast, keep docs accurate).
- No deprecations; use breaking changes.
- NO INLINE SCRIPTS EVER.
- NEVER send any message (iMessage, email, SMS, etc.) without explicit user confirmation:
  - Always show the full message text and ask: “I’m going to send this: <message>. Send? (y/n)”

Git workflow:
- Trunk-based development: work on `main` by default and push small, surgical commits directly to `main`.
- Use branches only when Josh explicitly asks, direct push is blocked, or a disposable local experiment is needed.
- For multi-issue work, commit and push one issue at a time; verify GitHub Actions for each pushed commit before continuing to the next issue.
- Do not leave completed maintainer work parked on a Codex branch.

OpenClaw packaging:
- The gateway package must include Control UI assets (run `pnpm ui:build` in the Nix build).
- Product intent: ship a working Nix package for OpenClaw users, not just a pin mirror. `openclaw-gateway` is the source-built runnable gateway for Linux and macOS; `openclaw-app` is the Darwin-only desktop app from upstream's signed/notarized app artifact; `openclaw` is the batteries-included bundle.
- User-facing docs should lead with one package: `openclaw`. Treat `openclaw-gateway` and `openclaw-app` as advanced/component outputs for checks, modules, and debugging, not separate product tracks. Runtime tools are internal implementation detail, not a public package surface.
- README should be agent-first: the main setup path is "tell your coding agent you want OpenClaw using Nix, then let it inspect/interview/configure/verify." Manual commands are reference material, not the primary onboarding path.
- Do not split the repo into separate desktop/server tracks. Segment package outputs, keep one simple user-facing flake.
- DJTBOT deployment freshness is downstream and out of scope unless explicitly requested; fix public packaging first.
- Release-flow context lives in `openclaw/maintainers` and `openclaw/openclaw`. Read `openclaw/maintainers/release/README.md`, `release/macos.md`, and the public `openclaw/openclaw` release workflows before changing update policy.
- Public OpenClaw tags/GitHub releases can exist before macOS app assets. The public `macos-release.yml` is validation-only; private release workflows upload `.zip`, `.dmg`, and `.dSYM.zip` later.
- Missing public macOS assets on the newest stable release is not proof the source gateway is unpackageable. Treat it as "not a full desktop-packageable release yet."
- Prefer the upstream `.zip` app artifact for `openclaw-app`, but verify unpacked contents contain an `.app`; do not trust filename alone.

Golden path for pins (yolo + manual bumps):
- Hourly GitHub Action **Yolo Update Pins** should select the newest stable upstream OpenClaw release that satisfies the full Nix package contract: gateway builds/runs on Linux and macOS, and Darwin desktop app artifact is available for the same release.
- If newer stable releases lack public macOS assets, yolo should report them as skipped source-only/incomplete desktop releases and promote the newest full packageable stable release that passes checks.
- Checks mean the Nix-owned package contract: source build, generated config options, package contents, smoke startup, module activation, and matching macOS app artifact. Do not gate yolo on the full upstream Vitest suite; upstream owns source test health.
- `scripts/update-pins.sh` is the updater boundary:
  - `select` resolves release candidates, source tag SHAs, skipped assetless stable releases, and the exact app asset URL for the chosen full packageable release
  - `apply <tag> <sha> <app-url>` materializes the source pin, app pin, `pnpmDepsHash`, and generated config options for that exact release
- Manual bump (rare): trigger yolo manually with `gh workflow run "Yolo Update Pins"`.
- To verify freshness: compare `nix/sources/openclaw-source.nix` and `nix/packages/openclaw-app.nix` to the newest full packageable stable release, not blindly to GitHub's newest stable tag.
- Recovery note: repin to the latest full packageable stable OpenClaw release first, fix Nix-owned seams before touching gateway behavior, and avoid broad `gateway-postpatch.sh` behavior hacks.

Daily Codex maintainer automation:
- Automation id: `nix-openclaw-maintainer` (daily around 06:00 Europe/Amsterdam).
- The daily automation is an agentic maintainer run, not a passive alert and not a second release pipeline.
- Product intent is simple: keep OpenClaw packaged with Nix for real users on macOS and Linux.
- Start from upstream/yolo/CI state: inspect latest OpenClaw releases, recent **Yolo Update Pins** runs, recent `CI` runs, current pins, and `scripts/update-pins.sh select`.
- macOS app publishing is out of scope for this repo and this automation. If upstream forgets to publish public macOS app assets, classify it as upstream release-contract lag and keep packaging the newest full packageable stable release.
- If yolo and CI are healthy, report briefly and stop.
- If broken, diagnose deeply and classify the failure: upstream release-contract lag, nix-openclaw packaging bug, CI infrastructure issue, or automation/repo-policy drift.
- If the fix is in nix-openclaw, edit the repo, self-review the diff until the review has no actionable findings, run the full gate, commit directly to `main`, and push directly to `main`.
- Full gate means the relevant targeted checks plus `scripts/check-flake-lock-owners.sh`, selector test, updater shell syntax, workflow YAML parse, `nix flake show --accept-flake-config`, Linux CI aggregator, Darwin CI aggregator when available, and `scripts/hm-activation-macos.sh` when a macOS runner is available.
- No force push. No weakening Nix-owned package checks to get green. No separate PR flow unless direct push is blocked by GitHub policy.
- Do not create a competing release process; yolo remains the release updater. The daily run repairs the packaging/process when yolo cannot do its job.
- If it cannot safely fix the issue, leave a concise report with evidence, the exact failing command/run, and the next concrete repair step.

CI polling (hard rule):
- Never say "I'll keep polling" unless you are **already** running a blocking loop.
- If you must report status, confirm the loop is active (`tmux ls` / session name).
- Use a blocking bash loop in tmux (preferred) or a sub-agent; do not fake it.
- Example: `tmux new -s nix-openclaw-ci '/tmp/poll-nix-openclaw-ci.sh'`.

Philosophy:

The Zen of ~~Python~~ OpenClaw, ~~by~~ shamelessly stolen from Tim Peters

Beautiful is better than ugly.  
Explicit is better than implicit.  
Simple is better than complex.  
Complex is better than complicated.  
Flat is better than nested.  
Sparse is better than dense.  
Readability counts.  
Special cases aren't special enough to break the rules.  
Although practicality beats purity.  
Errors should never pass silently.  
Unless explicitly silenced.  
In the face of ambiguity, refuse the temptation to guess.  
There should be one-- and preferably only one --obvious way to do it.  
Although that way may not be obvious at first unless you're Dutch.  
Now is better than never.  
Although never is often better than *right* now.  
If the implementation is hard to explain, it's a bad idea.  
If the implementation is easy to explain, it may be a good idea.  
Namespaces are one honking great idea -- let's do more of those!

Nix file policy:
- No inline file contents in Nix code, ever.
- Always reference explicit file paths (keep docs as real files in the repo).
- No inline scripts in Nix code, ever (use repo scripts and reference their paths).
- No files longer than 400 LOC without user alignment; refactor as you go.
