# Glimpse

Compact native macOS menu-bar system monitor. Read README.md and docs/design.md before related work. This repository currently contains documentation only; no app target or build command exists yet.

## Constraints

- MIT licensed. Independent implementation; do not copy GPL-only code from iGlance into the MIT project.
- Keep the default menu-bar footprint to one compact icon. Clicking it reveals detailed live status. Persistent numeric blocks are optional.
- Initial deployment target: macOS 12, native arm64 and x86_64. Do not raise it for a UI convenience. Lowering it requires reproducible build/runtime and performance evidence.
- Shared background sampling; native counters, measured elapsed time, no subprocess polling. Missing data is not zero.
- Performance budgets and compatibility in the design are targets, not verified claims.
- Keep documentation synchronized with implementation. Add concrete build/test instructions when a runnable target exists.

## Project Tracking

github_repo: nairdaleo/Glimpse
github_project: 10 "Glimpse" (https://github.com/users/nairdaleo/projects/10)
Status = Todo / In Progress / Done
Use repository issues and the linked GitHub project for work tracking.
