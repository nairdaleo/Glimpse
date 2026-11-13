# Glimpse

A compact, configurable, open-source system monitor for the macOS menu bar.

Glimpse is designed around a small icon containing three configurable meter columns. Each column fills and changes colour according to information you choose. Click the icon to reveal detailed live status and short history graphs. Enable the optional MenuMeters-style upload/download block when you want bandwidth numbers visible all the time. Other numeric blocks are a future option.

**Status: first development version.** A runnable app can be built from source. There is no signed/notarized public release yet. Glimpse is a working name.

## Current experience

- One compact icon by default, with configurable metrics, colours, thresholds, and column order.
- Click for exact readings, labels, short histories, and collection status.
- Optional upload/download readout with a stable width.
- Native monitoring designed for low overhead; performance budgets still need measurement.
- Local settings and measurements; no account or analytics service.

## Compatibility

The deployment target is **macOS 12 Monterey**, with a universal Intel and Apple silicon build. Native-reader tests run on the current Apple silicon development Mac; Monterey and Intel runtime support still need verification. macOS 12 is the oldest deployment target supported by the currently selected Xcode 27.2 toolchain. Going lower remains a tracked investigation.

The menu-bar renderer will use AppKit. Settings may use SwiftUI APIs available on macOS 12. Newer convenience APIs must not raise the minimum version without a documented reason.

## Documentation and development

- [Public project board](https://github.com/users/nairdaleo/projects/10): upcoming work and validation.
- [Design](docs/design.md): user experience, sampling, compatibility, performance goals, and validation.
- [iGlance assessment](docs/iglance-assessment.md): what we studied and what remains unverified.
- [License decision](docs/licensing.md): why MIT was selected and how third-party code is handled.
- [Development and validation](docs/development.md): build, run, test, metric definitions, and remaining checks.

With Xcode 27.2 selected, build and open the app:

```bash
./scripts/build-app.sh
open build/Glimpse.app
```

Click the three-column icon for detailed live status. Choose **Settings…** to change columns, colours, warning thresholds, units, interface, refresh cadence, and the optional bandwidth block. Reopening the app opens settings if the icon is hidden by menu-bar crowding.

```bash
swift test
ARCH=universal ./scripts/build-app.sh
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
```

There are no external package dependencies. The build script applies an ad-hoc development signature, suitable for local testing rather than distribution. Do not disable Gatekeeper to run a downloaded build.

Contributions are welcome through issues and pull requests. For proposed behaviour, identify the user need and discuss changes to the design before implementation. Include relevant accuracy or performance evidence for changes to monitoring. Do not commit signing credentials or personal diagnostics.

## Inspiration and license

Inspired by the glanceable monitoring of MenuMeters and iGlance, and by the compact footprint of Tailscale's menu-bar icon. This is an independent project; no upstream app code or branding has been imported.

Copyright (c) 2026 Tasty Jam App Development. Released under the [MIT License](LICENSE). Third-party components, if introduced, retain their own licenses and notices.
