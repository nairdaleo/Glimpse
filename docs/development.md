# Development and validation

## Build and run

The current verified development toolchain is Xcode 27.2. Select it with `xcode-select` as appropriate for your installation. SwiftPM resolves the pinned Sparkle 2.9.6 framework; no other package manager is required. The package manifest uses Swift tools 5.9; older developer toolchains have not been tested. The app deployment target is macOS 12, which is separate from the macOS version needed to run Xcode.

```bash
swift test
./scripts/build-app.sh
open build/Glimpse.app
```

The app runs in the menu bar without a Dock icon. Clicking its icon toggles detailed status. Settings has a drag-to-organize shelf of one to eight meters, width scale, assignment/order, palette, optional threshold colours/direction, monochrome meters, bandwidth readout/units, interface, refresh and reset. Add or select **Upload / Download** for a two-colour meter: upper half upload, lower half download. Exact rates remain independent in the tooltip and detail panels.

Dropdown cards are dragged into order, hidden and restored only in the settings organizer. Choose 1–8 cards per row and a shared card width; each card has size, graph colour and history options. Clicking a dropdown card opens its editor. The popup sizes to its row maxima and column widths, with scrolling when constrained by the screen. The gear opens settings, including opt-in login/update controls. Reopening the app opens settings. For a direct settings launch:

```bash
open build/Glimpse.app --args --settings
```

The output is `build/Glimpse.app`, ad-hoc signed by default. `CODESIGN_IDENTITY` selects a certificate for development signing; no private key is exported. The script bundles/re-signs Sparkle and the login helper before signing the main app. The script is safe to rerun. To build both native architectures:

```bash
ARCH=universal ./scripts/build-app.sh
lipo -info build/Glimpse.app/Contents/MacOS/Glimpse
xcrun vtool -show-build build/Glimpse.app/Contents/MacOS/Glimpse
codesign --verify --deep --strict build/Glimpse.app
```

Start at login is configured in the General settings tab. Turn it off, quit via the status panel and move the app to the Trash to uninstall. Remove any separately/manually added login item in macOS Login Items. Preferences remain in the `com.tastyjam.glimpse` defaults domain; remove them separately only if you want to reset saved choices. Update signing and distribution details are in [updates.md](updates.md).

## Reader diagnostic

```bash
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
```

This terminal mode reads all metrics twice, separated by 1.1 seconds to establish rate baselines. It prints current values and the measured interface without launching the menu-bar UI. It does not change settings, export private diagnostics, launch shell polling, or upload anything.

## Architecture

- `GlimpseCore` contains Sendable value snapshots/settings, normalization and explicit-unit formatting, CPU/rate arithmetic, threshold handling, and bounded history. Invalid settings are repaired to safe defaults.
- `GlimpseMonitor.NativeSampler` owns mutable native-reader state. It has no internal timer and is not thread safe by itself. The app's private SamplingWorker confines every operation to one serial utility queue; only value snapshots cross back to the main thread.
- `GlimpseApp.MonitoringStore` owns the main-thread display state, persisted settings, timer lifecycle, and sleep/power notifications. Old results from replaced configurations are discarded.
- `StatusController` renders a single AppKit status item and presents the SwiftUI status panel. `SettingsView` edits settings through the store. Sparkle is the only bundled external framework; there is no web runtime.
- `BandwidthReadout` measures a four-character numeric budget in the displayed units instead of reserving 80 points. `DuplexGaugeLayout` keeps directional fills independent. `StatusPanelLayout` is shared by the SwiftUI view and popover controller so their sizing agrees.

The default icon collects CPU, memory and download. The optional bandwidth block also demands upload. Opening status demands only visible dropdown panels; hidden panels add no demand unless a meter needs them. Opening settings permits network inventory enumeration for the picker without publishing hidden readings or creating rate baselines. CPU and network read at the selected cadence; memory caches for 2 seconds, battery for 10, disk capacity for 30 and thermal state for 5. Low Power Mode imposes a 5-second minimum cadence. Sampling pauses during system sleep and rate baselines are reset before wake sampling. Settings changes preserve elapsed-time rate calculations; a newly selected interface begins with an unavailable baseline reading.

## What the numbers mean

- CPU: busy tick deltas divided by total tick deltas across the machine; normalized 0–100%, not per-core percentages added together.
- Memory: active + wired + compressor physical pages divided by physical RAM. Inactive cache is excluded. This is explicitly labelled usage, not memory pressure; Activity Monitor's category accounting is different. Absolute used/total capacities appear in detail.
- Network: 64-bit native interface-counter deltas divided by measured monotonic elapsed time. Automatic selection prefers the primary active physical interface, with an active physical fallback. IPv4 and IPv6 primary metadata are considered. A single explicitly selected tunnel is allowed. Physical and tunnel counters are never summed. Interface and read failures reset the baseline rather than creating a spike.
- Disk: root volume total minus Foundation available capacity; no summing of APFS volumes. This is capacity, not disk I/O throughput.
- Battery: IOKit internal battery current/max capacity, with charging/power-source status. A desktop without a battery is unavailable, not 0%.
- Thermal: the supported system thermal-state ordinal, displayed as Nominal/Fair/Serious/Critical. No estimated Celsius temperature or fan RPM is shown.

Bandwidth units are decimal B/s, KB/s, MB/s, etc., or decimal bits/s when selected. The **Network column full at** field follows the selected units: its default is 12.5 MB/s in byte mode or 100 Mb/s in bit mode. Switching units converts the displayed number and label without changing the stored bytes/second ceiling; edits in either mode convert back to bytes/second. That is a display scale, not measured link capacity. Percentage fill and threshold colours do not diagnose hardware health.

History is bounded to five minutes and at most 600 points per metric. Cached readings keep their collection timestamps and are not appended repeatedly. Unavailable samples and periods where a previously collected metric is no longer demanded break the graph. Closing the panel does not keep panel-only collectors running.

## Evidence and limits

Current evidence on the Apple silicon development Mac:

- Core arithmetic, settings migration/repair, history bounds/gaps, native route parsing/64-bit counters, interface policy, failure recovery, demand and cache behaviour have automated tests.
- The suite covers layout migration/limits, identity-safe reordering, hidden panel demand, threshold boundaries, native counter accuracy, and widget geometry/raster creation. Exact current counts are recorded in verification output rather than treated as a product requirement.
- A live integration test and terminal diagnostic exercise actual CPU, VM, network, battery, disk and thermal readers without a privileged helper.
- A universal release build contains native arm64 and x86_64 slices. Both declare macOS 12.0 minimum deployment. The local ad-hoc bundle signature verifies. Xcode warns that x86_64 is deprecated on the development SDK; this does not establish older Intel runtime support.

Not verified: macOS 12 runtime, Intel hardware runtime, live VPN/physical-interface transitions, actual system sleep/wake, VoiceOver/keyboard/appearance/crowded-menu-bar behaviour, eight-hour stability, and release performance budgets. Computer-use inspection could not start because its Node runtime was unavailable. Successful compilation and native-reader tests do not prove these UI and hardware behaviours.

The proposed CPU/RSS/energy budgets in the design are still acceptance targets. Source-derived architecture choices are not performance measurements. Signed update installation, login registration/logging out, notarization and sandboxed App Store distribution need runtime/release validation. There is no public notarized release, tip jar/review integration, sensor-temperature implementation, import/export UI, or disk-I/O meter yet. Track these investigations in the [GitHub project](https://github.com/users/nairdaleo/projects/10).
