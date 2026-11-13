# Glimpse

Compact native macOS menu-bar system monitor. Read README.md, docs/design.md, and docs/development.md before related work. The first native development app is implemented as a dependency-free Swift package.

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
- `build/Glimpse.app/Contents/MacOS/Glimpse --diagnose` samples native readers without opening UI.
- Runtime on Intel/macOS 12, live VPN/interface transitions, sleep/wake, UI interaction and release performance budgets require explicit verification; compilation is not runtime coverage.
- Source responsibilities: GlimpseCore = pure models/calculations/settings/history; GlimpseMonitor = native readers; GlimpseApp = queue confinement, persistence, AppKit status item and SwiftUI interface.

## Project Tracking

github_repo: nairdaleo/Glimpse
github_project: 10 "Glimpse" (https://github.com/users/nairdaleo/projects/10)
Status = Todo / In Progress / Done
Use repository issues and the linked GitHub project for work tracking.
