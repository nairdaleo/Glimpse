# Architecture

How Glimpse is put together: modules, data flow, threading, the two editions and the build/release pipeline. **Keep this file current**: any change to module boundaries, data flow, threading, persistence, editions, scripts or the release pipeline updates it in the same pull request.

## Modules

SwiftPM package (`Package.swift`, tools 5.9, macOS 12). Dependencies only point downward.

```
GlimpseApp ──► GlimpseMonitor ──► GlimpseCore
     │                                ▲
     └────────────────────────────────┘
GlimpseLoginHelper (standalone, macOS 12 login item)
Sparkle 2.10.1 (direct-download edition only)
```

| Target | Role | Main files |
| --- | --- | --- |
| `GlimpseCore` | Pure, `Sendable` value types and arithmetic. No AppKit, no I/O. Everything here is unit-tested. | `Models.swift` (`MetricID`, `MetricReading`, `Snapshot`, `MeterColour`), `Settings.swift` (`AppSettings`, columns, panels, migration and repair of saved settings), `Calculations.swift` (counter rates, CPU usage, formatting), `MetricHistory.swift` / `NetworkHistory.swift` (bounded histories), `NetworkModels.swift`, `Organization.swift` (identity-safe reordering), `ThresholdLatch.swift`, `BandwidthCeilingInput.swift` |
| `GlimpseMonitor` | Native readers. Mutable state, no timer, not thread safe by itself. | `NativeSampler.swift` (CPU ticks, VM statistics, disk capacity, IOKit battery, thermal state; per-metric caching and demand), `NetworkReader.swift` (64-bit interface counters, interface selection, rate tracking), `NetworkMetadata.swift` (interface type, addresses, DNS via SystemConfiguration) |
| `GlimpseApp` | The executable: lifecycle, threading, persistence, AppKit status item, SwiftUI panels and settings. | see below |
| `GlimpseLoginHelper` | Tiny helper app embedded at `Contents/Library/LoginItems` for start-at-login on macOS 12 (`SMLoginItemSetEnabled`). macOS 13+ uses `SMAppService` and ignores it. | `GlimpseLoginHelper.swift` |

`GlimpseApp` files by responsibility:

| Area | Files |
| --- | --- |
| Entry and modes | `GlimpseMain.swift`: `AppDelegate`; command-line modes `--diagnose` (print native readings, no UI), `--render-cards <dir>` (`CardRenderer.swift`), `--settings` |
| State and sampling | `MonitoringStore.swift`: main-thread `@Published` snapshot/settings, settings persistence in `UserDefaults`, the sampling timer, sleep/wake and Low Power Mode handling; its private `SamplingWorker` owns the `NativeSampler` on one serial utility queue |
| Menu-bar icon | `StatusController.swift` (status item, popover lifecycle), `MeterImage.swift` (draws the meter image), `StatusWidgetLayout.swift` / `DuplexGaugeLayout`, `BandwidthReadout.swift` |
| Dropdown panel | `StatusPanel.swift`, `StatusPanelLayout.swift` (shared sizing for the SwiftUI view and the popover), `MetricCardContent.swift` (cards and history graphs), `NetworkPresentation.swift` |
| Settings | `SettingsView.swift` (tabs, meter and panel editors), `OrganizationDrop.swift` (AppKit drag and drop for reordering), `ColourPicker.swift`, `AboutView.swift` |
| System services | `LifecycleServices.swift`: start at login, Sparkle updater (direct edition), **Remove Glimpse…** |

## Data flow

```
DispatchSourceTimer (main, selected cadence; paused during sleep)
        │ demand = metrics needed by meters + open panel + open settings
        ▼
SamplingWorker  ── serial queue "com.tastyjam.glimpse.sampling" ──►  NativeSampler.sample()
        │                                                                 │ native counters, caches
        ◄──────────────────── Snapshot (value type) ──────────────────────┘
        ▼
MonitoringStore (main thread) ── @Published snapshot/settings ──► StatusController.render() ──► MeterImage
                                                                └► StatusPanel / SettingsView (SwiftUI, only while visible)
```

- Only value snapshots cross from the sampling queue to the main thread. Results from a configuration that has since been replaced are discarded.
- Rates use measured monotonic elapsed time between samples; a failed or missing read is reported as unavailable, never as zero. Baselines reset on interface changes, read failures and wake.
- Demand-driven: a metric is read only while a meter, the open panel or open settings needs it. Slow metrics are cached (memory 2 s, thermal 5 s, battery 10 s, disk 30 s).
- UI exists only while visible, because hidden SwiftUI hosting views keep re-rendering on every sample (idle CPU and memory):
  - The detail panel's `NSHostingController` is created when the popover opens (`StatusController.togglePanel`) and released in `popoverDidClose`.
  - The Settings window is released in `AppDelegate.windowWillClose` and rebuilt by `showSettings` the next time Settings opens.
  - `StatusController` stops drawing the menu-bar icon while the displays sleep (`NSWorkspace.screensDidSleep/WakeNotification`, plus `CGDisplayIsAsleep` at launch); sampling and history keep running.
- Everything is event-driven: no polling loops besides the one sampling timer, no subprocesses.

Metric definitions and the evidence behind them are in [development.md](development.md#what-the-numbers-mean).

## Persistence

- Settings: `AppSettings` encoded in the app's `UserDefaults` domain `com.tastyjam.glimpse` (sandbox container for the App Store edition). Decoding repairs invalid values to safe defaults and migrates older layouts; new fields must keep old settings working.
- Sparkle stores its own preferences (`SU*` keys). Nothing is sent anywhere; there is no analytics.

## Editions

One source tree, two builds. The App Store edition is selected at build time with `GLIMPSE_APP_STORE=1` (read by `Package.swift`), which drops the Sparkle dependency from `GlimpseApp` and defines the Swift flag `APP_STORE`.

| | Direct download | Mac App Store |
| --- | --- | --- |
| Build | `scripts/build-app.sh` → `build/Glimpse.app` | `APP_STORE=1 scripts/build-app.sh` or `scripts/make-pkg.sh` → `build/AppStore/Glimpse.app` |
| Sandbox | No | Yes (`Configuration/AppStore.entitlements` + profile identifiers) |
| Updates | Sparkle, opt-in, feed `appcast.xml` on `main` (`Configuration/Updates.plist`) | App Store |
| Support | Ko-fi link in About | No external payment links allowed; optional in-app tips are tracked in #7 |
| Code differences | — | `#if APP_STORE` in `LifecycleServices.swift` (no updater), `SettingsView.swift` (no **Remove Glimpse…**) |

## Build and release pipeline

| Script | Does |
| --- | --- |
| `scripts/build-app.sh` | `swift build`, assembles the `.app` bundle (Info.plist, resources, icon, Sparkle or sandbox entitlements, login helper), signs inside-out. `ARCH`, `VERSION`, `BUILD_NUMBER`, `CODESIGN_IDENTITY`, `APP_STORE` |
| `scripts/make-icon.sh` | Renders the icon master `packaging/icon/Glimpse.svg` to `.icns` (called by `build-app.sh`) |
| `scripts/make-dmg.sh` | Universal build + drag-to-Applications DMG; Developer ID signing, notarization and stapling when credentials are present |
| `scripts/make-pkg.sh` | App Store edition `.pkg`; `--upload` sends it to App Store Connect and tags the build |
| `scripts/release.sh` | The whole release: tests, notarized DMG, tag, GitHub release, App Store upload, Sparkle appcast, Homebrew cask |

Releases run only on the owner's Mac; GitHub holds no signing, Sparkle or App Store Connect secrets. CI (`.github/workflows/ci.yml`) tests and builds both editions on Apple silicon and Intel runners and scans for secrets. Build numbers are the commit count. Details: [releasing.md](releasing.md); manual equivalents of every step: [CONTRIBUTING.md](../CONTRIBUTING.md#doing-everything-by-hand).

## Tests

| Target | Covers |
| --- | --- |
| `GlimpseCoreTests` | Arithmetic, formatting, settings migration and repair, histories, reordering, thresholds |
| `GlimpseMonitorTests` | Native readers against the live system, counter parsing, interface policy, demand and caching |
| `GlimpseAppTests` | Panel layout, widget geometry and rendering, card rendering (`GLIMPSE_RENDER_ARTIFACTS` saves PNGs), drag-and-drop rules |
