# Glimpse

Compact native macOS menu-bar system monitor. Read README.md, docs/design.md, docs/development.md, and docs/updates.md before related work. The native app uses SwiftPM with pinned Sparkle for direct-download updates.

## Constraints

- MIT licensed. Independent implementation; do not copy GPL-only code from iGlance into the MIT project.
- Keep the default menu-bar footprint to one compact icon. Clicking it reveals detailed live status. Persistent numeric blocks are optional.
- Initial deployment target: macOS 12, native arm64 and x86_64. Do not raise it for a UI convenience. Lowering it requires reproducible build/runtime and performance evidence.
- Shared background sampling; native counters, measured elapsed time, no subprocess polling. Missing data is not zero.
- Performance budgets and compatibility in the design are targets, not verified claims.
- Keep documentation synchronized with implementation. Add concrete build/test instructions when a runnable target exists.

## Build and verify

- `swift test` runs core and native-reader tests.
- `./scripts/build-app.sh` builds and ad-hoc signs `build/Glimpse.app` for the host architecture.
- `ARCH=universal ./scripts/build-app.sh` builds arm64 and x86_64 together.
- `scripts/make-pkg.sh` builds the sandboxed, Sparkle-free Mac App Store edition (`APP_STORE=1`, Swift flag `APP_STORE`) into `build/AppStore/` and a `.pkg`; `UPLOAD=1` uploads it to App Store Connect. That upload is local only: App Store Connect credentials are never added to GitHub secrets.
- `build/Glimpse.app/Contents/MacOS/Glimpse --diagnose` samples native readers without opening UI.
- `build/Glimpse.app/Contents/MacOS/Glimpse --render-cards <dir>` renders saved panels at every card size with live data (light/dark) for visual audits; relaunch the app after each feature so the user can verify.
- CI (`.github/workflows/ci.yml`) runs tests, universal build and diagnostics on Apple silicon and Intel runners plus a gitleaks scan. Releases: `vX.Y.Z-rc.N` tags → signed, notarized pre-release; promote via the Promote workflow (docs/releasing.md). Owner-only steps carry the `needs-owner` issue label.
- Runtime on Intel/macOS 12, live VPN/interface transitions, sleep/wake, UI interaction and release performance budgets require explicit verification; compilation is not runtime coverage.
- Source responsibilities: GlimpseCore = pure models/calculations/settings/history; GlimpseMonitor = native readers; GlimpseApp = queue confinement, persistence, AppKit status item and SwiftUI interface.
- Meters support one to eight stable identities and width scale 0.75...1.5. Dropdown panels are independently ordered/removed; missing new settings must preserve legacy layouts.
- Combined network is a column display mode requiring separate upload/download readings, never a net scalar. Its upper half is upload and lower half download, with independent colours/threshold state.
- Detailed View arrangement/removal is settings-only. Cards open their editor when clicked. Panel columns1...8, width120...240 and per-card size/colour/history drive StatusPanelLayout and screen-bounded popover sizing.
- Update public metadata is in Configuration/Updates.plist; private signing key remains in the login Keychain account com.tastyjam.glimpse. Never export/commit it. No signed downloadable release has been published.
- Login/updates are opt-in. A separate Mac App Store build must exclude Sparkle, validate the sandbox, and keep features free; tips/reviews remain release work.

## Project Tracking

github_repo: nairdaleo/Glimpse
github_project: 10 "Glimpse" (https://github.com/users/nairdaleo/projects/10)
Status = Todo / In Progress / Done
Use repository issues and the linked GitHub project for work tracking.
