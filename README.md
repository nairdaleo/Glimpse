# Glimpse

A compact, configurable, open-source system monitor for the macOS menu bar.

Glimpse is designed around a small icon containing one to eight configurable meter columns. Each column fills and changes colour according to information you choose. Drag meters into order in settings and adjust their width. The special **Upload / Download** meter fills upward from its center for upload and downward for download, with separate colours. Enable the compact numeric bandwidth readout when you want exact speeds visible all the time.

Click the icon for live status and recent graphs. Arrange and hide dropdown cards in settings, choose 1–8 cards per row and their width, and adjust each card's size, graph colour and history. The dropdown expands to fit the selected grid within screen bounds. Clicking a dropdown card opens its settings; the dropdown itself has no rearrangement or hide controls.

**Status: first development version.** A runnable app can be built from source. There is no signed/notarized public release yet. Glimpse is a working name.

## Current experience

- One compact icon by default, with configurable meter count, width, metrics, colours, thresholds, and drag-to-reorder controls.
- Click for exact readings, labels, short histories, and collection status in a resizable card grid.
- Optional upload/download readout with a stable width.
- Native monitoring designed for low overhead; performance budgets still need measurement.
- Local settings and measurements; no account or analytics service.
- Opt-in start at login, automatic update checks/downloads, and manual update checks.

## Compatibility

The deployment target is **macOS 12 Monterey**, with a universal Intel and Apple silicon build. Native-reader tests run on the current Apple silicon development Mac; Monterey and Intel runtime support still need verification. macOS 12 is the oldest deployment target supported by the currently selected Xcode 27.2 toolchain. Going lower remains a tracked investigation.

The menu-bar renderer will use AppKit. Settings may use SwiftUI APIs available on macOS 12. Newer convenience APIs must not raise the minimum version without a documented reason.

## Documentation and development

- [Public project board](https://github.com/users/nairdaleo/projects/10): upcoming work and validation.
- [Design](docs/design.md): user experience, sampling, compatibility, performance goals, and validation.
- [iGlance assessment](docs/iglance-assessment.md): what we studied and what remains unverified.
- [License decision](docs/licensing.md): why MIT was selected and how third-party code is handled.
- [Development and validation](docs/development.md): build, run, test, metric definitions, and remaining checks.
- [Updates and login](docs/updates.md): signed update configuration, login helper and free Mac App Store roadmap.

With Xcode 27.2 selected, build and open the app:

```bash
./scripts/build-app.sh
open build/Glimpse.app
```

Click the icon for detailed live status. The gear button opens settings for meters, dropdown panels, colours, warning thresholds, units, interface, refresh cadence, login and updates. Reopening the app opens settings if the icon is hidden by menu-bar crowding.

```bash
swift test
ARCH=universal ./scripts/build-app.sh
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
```

Sparkle 2.9.6 is the sole external dependency, pinned by SwiftPM for signed direct-download updates. The build script defaults to an ad-hoc signature; set `CODESIGN_IDENTITY` to a certificate identity for development signing. Distribution requires Developer ID signing and notarization. The configured update feed has no downloadable public release yet. Do not disable Gatekeeper to run a downloaded build.

Glimpse's monitoring features will remain fully free. Optional developer tips and review requests are planned for a separate Mac App Store edition; they do not unlock features. See the distribution roadmap before preparing a store submission.

Contributions are welcome through issues and pull requests. For proposed behaviour, identify the user need and discuss changes to the design before implementation. Include relevant accuracy or performance evidence for changes to monitoring. Do not commit signing credentials or personal diagnostics.

## Inspiration and license

Inspired by the glanceable monitoring of MenuMeters and iGlance, and by the compact footprint of Tailscale's menu-bar icon. This is an independent project; no upstream app code or branding has been imported.

Copyright (c) 2026 Tasty Jam App Development. Released under the [MIT License](LICENSE). Third-party components, if introduced, retain their own licenses and notices.
