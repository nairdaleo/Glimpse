# Glimpse

Compact native macOS menu-bar system monitor. This file is public: it is the shared guide for any AI coding agent working on Glimpse, whoever runs it. CONTRIBUTING.md's AI guidelines apply to the humans behind the agents.

Read docs/architecture.md first, then README.md, CONTRIBUTING.md, docs/design.md, docs/development.md and docs/updates.md before related work. The native app uses SwiftPM with pinned Sparkle for direct-download updates.

## Constraints

- MIT licensed. Independent implementation; do not copy GPL-only code from iGlance into the MIT project.
- Keep the default menu-bar footprint to one compact icon. Clicking it reveals detailed live status. Persistent numeric blocks are optional.
- Initial deployment target: macOS 12, native arm64 and x86_64. Do not raise it for a UI convenience. Lowering it requires reproducible build/runtime and performance evidence.
- Shared background sampling; native counters, measured elapsed time, no subprocess polling. Missing data is not zero.
- Performance budgets and compatibility in the design are targets, not verified claims.
- Keep documentation synchronized with implementation. Add concrete build/test instructions when a runnable target exists.
- **Keep docs/architecture.md current**: any change to modules, file responsibilities, data flow, threading, persistence, editions (`APP_STORE`), scripts, CI or the release pipeline updates it in the same commit or pull request. Manual build and CI steps live in docs/development.md and manual release steps in docs/releasing.md; update them when a script or workflow changes.

## Build and verify

- `swift test` runs core and native-reader tests.
- `./scripts/build-app.sh` builds and ad-hoc signs `build/Glimpse.app` for the host architecture.
- `ARCH=universal ./scripts/build-app.sh` builds arm64 and x86_64 together.
- The app icon master is `packaging/icon/Glimpse.svg` (original artwork; SF Symbols may not be used in icons). `scripts/make-icon.sh` renders it to `.icns`; `build-app.sh` embeds it in both editions.
- `scripts/make-pkg.sh` builds the sandboxed, Sparkle-free Mac App Store edition (`APP_STORE=1`, Swift flag `APP_STORE`) into `build/AppStore/` and a `.pkg`; `--env <file> --version x.y.z --upload` uploads it to App Store Connect (the `KEYS_ENV`/`VERSION`/`UPLOAD=1` variables still work). That upload is local only: App Store Connect credentials are never added to GitHub secrets.
- `build/Glimpse.app/Contents/MacOS/Glimpse --diagnose` samples native readers without opening UI.
- `build/Glimpse.app/Contents/MacOS/Glimpse --render-cards <dir>` renders saved panels at every card size with live data (light/dark) for visual audits. After a UI change, rebuild and relaunch the app so the change can be checked by eye.
- CI (`.github/workflows/ci.yml`) runs tests, universal build and diagnostics on Apple silicon and Intel runners plus a gitleaks scan. Releases are local only: `scripts/release.sh --env <file> --version x.y.z [--rc N]` notarizes, publishes the GitHub release, appcast, Homebrew cask and App Store upload (docs/releasing.md). Never add signing, Sparkle or App Store Connect secrets to GitHub, and never name local file paths in this public repo. Steps only the maintainer can do (accounts, certificates, payments, releases, design approvals) carry the `needs-owner` issue label; agents skip those issues and leave a comment saying exactly what the maintainer must do.
- Runtime on Intel/macOS 12, live VPN/interface transitions, sleep/wake, UI interaction and release performance budgets require explicit verification; compilation is not runtime coverage.
- Source responsibilities: GlimpseCore = pure models/calculations/settings/history; GlimpseMonitor = native readers; GlimpseApp = queue confinement, persistence, AppKit status item and SwiftUI interface.
- Meters support one to eight stable identities and width scale 0.75...1.5. Dropdown panels are independently ordered/removed; missing new settings must preserve legacy layouts.
- Combined network is a column display mode requiring separate upload/download readings, never a net scalar. Its upper half is upload and lower half download, with independent colours/threshold state.
- Detailed View arrangement/removal is settings-only. Cards open their editor when clicked. Panel columns1...8, width120...240 and per-card size/colour/history drive StatusPanelLayout and screen-bounded popover sizing.
- Update public metadata is in Configuration/Updates.plist; private signing key remains in the login Keychain account com.tastyjam.glimpse. Never export/commit it. Signed, notarized releases are published from the owner's Mac with scripts/release.sh.
- Login/updates are opt-in. A separate Mac App Store build must exclude Sparkle, validate the sandbox, and keep features free; tips/reviews remain release work.

## Working rules for agents

- Run `swift test` before every commit and keep commits small and focused; describe what was verified and what was not (hardware, macOS 12, Intel, sleep/wake).
- Mark agent-written commits with a `Co-Authored-By` trailer for the model.
- Never read, print, move or commit secrets: certificates, `.p12`/`.p8` keys, provisioning profiles, env files, the Sparkle private key. Never run `scripts/release.sh`, create tags or publish releases unless the maintainer asks in that session.
- Measure before claiming: performance and accuracy statements need the numbers and how they were taken (see docs/performance.md).
- Don't put local paths, hostnames, account emails or personal diagnostics in commits, issues or docs.
- Maintainers may keep extra, private agent instructions in `AGENTS.local.md` or `CLAUDE.local.md`; both are gitignored and must never be committed.

## Coding guidelines

Adapted from Andrej Karpathy's guidelines for reducing common LLM coding mistakes:

1. **Think before coding.** State assumptions explicitly. If a request has several readings, name them instead of picking one silently. If something is unclear, stop and ask. Say so when a simpler approach exists.
2. **Simplicity first.** Write the minimum code that solves the issue: no speculative features, single-use abstractions or unrequested configurability. If 200 lines could be 50, rewrite it.
3. **Surgical changes.** Touch only what the task needs. Don't reformat or refactor adjacent code, match the existing style, and remove only the imports, variables and functions your own change made unused.
4. **Goal-driven execution.** Turn the task into a check that can pass or fail: a test, `--diagnose` output, a card render or a measurement. Loop until it passes, and state for a multi-step task how each step will be verified.

## Project Tracking

github_repo: nairdaleo/Glimpse
github_project: 10 "Glimpse" (https://github.com/users/nairdaleo/projects/10)
Status = Todo / In Progress / Done
Use repository issues and the linked GitHub project for work tracking.
