# Glimpse

A compact, configurable, open-source system monitor for the macOS menu bar.

Glimpse is designed around a small icon containing three configurable meter columns. Each column fills and changes colour according to information you choose. Click the icon to reveal detailed live status and short history graphs. Add optional information blocks, including MenuMeters-style upload and download speeds, when you want numbers visible all the time.

**Status: design stage.** There is no runnable app or downloadable release yet. Glimpse is a working name.

## Planned experience

- One compact icon by default, with configurable metrics, colours, thresholds, and column order.
- Click for exact readings, labels, short histories, and collection status.
- Optional upload/download readout and other numeric blocks with stable widths.
- Native monitoring with low CPU, memory, and battery overhead.
- Local settings and measurements; no account or analytics service.

## Compatibility

The initial deployment target is **macOS 12 Monterey**, with native Intel and Apple silicon builds. This is a design target, not a tested compatibility claim. It is the oldest deployment target supported by the currently selected Xcode 27.2 toolchain. Going lower is worth evaluating only if an older release toolchain can preserve performance, maintainability, and verifiable support.

The menu-bar renderer will use AppKit. Settings may use SwiftUI APIs available on macOS 12. Newer convenience APIs must not raise the minimum version without a documented reason.

## Documentation and development

- [Public project board](https://github.com/users/nairdaleo/projects/10): upcoming work and validation.
- [Design](docs/design.md): user experience, sampling, compatibility, performance goals, and validation.
- [iGlance assessment](docs/iglance-assessment.md): what we studied and what remains unverified.
- [License decision](docs/licensing.md): why MIT was selected and how third-party code is handled.

The repository currently contains documentation only. No dependencies need installing and no build command exists yet. Once a runnable target is added, this README must provide exact setup, build, and test instructions.

Contributions are welcome through issues and pull requests. For proposed behaviour, identify the user need and discuss changes to the design before implementation. Include relevant accuracy or performance evidence for changes to monitoring. Do not commit signing credentials or personal diagnostics.

## Inspiration and license

Inspired by the glanceable monitoring of MenuMeters and iGlance, and by the compact footprint of Tailscale's menu-bar icon. This is an independent project; no upstream app code or branding has been imported.

Copyright (c) 2026 Tasty Jam App Development. Released under the [MIT License](LICENSE). Third-party components, if introduced, retain their own licenses and notices.
