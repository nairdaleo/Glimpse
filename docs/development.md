# Development and validation

## Build and run

The current verified development toolchain is Xcode 27.2. Select it with `xcode-select` as appropriate for your installation. No third-party package manager or dependencies are required. The package manifest uses Swift tools 5.9; older developer toolchains have not been tested. The app deployment target is macOS 12, which is separate from the macOS version needed to run Xcode.

```bash
swift test
./scripts/build-app.sh
open build/Glimpse.app
```

The app runs in the menu bar without a Dock icon. Clicking its icon toggles detailed status. Settings has column assignment/order, palette, optional threshold colours/direction, monochrome meters, bandwidth readout and units, interface, ceiling, refresh, and reset. Reopening the app opens settings. For a direct settings launch:

```bash
open build/Glimpse.app --args --settings
```

The output is `build/Glimpse.app`, ad-hoc signed for local development. The script is safe to rerun. To build both native architectures:

```bash
ARCH=universal ./scripts/build-app.sh
lipo -info build/Glimpse.app/Contents/MacOS/Glimpse
xcrun vtool -show-build build/Glimpse.app/Contents/MacOS/Glimpse
codesign --verify --deep --strict build/Glimpse.app
```

Launch-at-login is configured manually in macOS Login Items for now. Quit via the status panel, remove any login item, and move the app to the Trash to uninstall. Preferences remain in the `com.tastyjam.glimpse` defaults domain; remove them separately only if you want to reset saved choices.

## Reader diagnostic

```bash
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
```

This terminal mode reads all metrics twice, separated by 1.1 seconds to establish rate baselines. It prints current values and the measured interface without launching the menu-bar UI. It does not change settings, export private diagnostics, launch shell polling, or upload anything.

## Architecture

- `GlimpseCore` contains Sendable value snapshots/settings, normalization and explicit-unit formatting, CPU/rate arithmetic, threshold handling, and bounded history. Invalid settings are repaired to safe defaults.
- `GlimpseMonitor.NativeSampler` owns mutable native-reader state. It has no internal timer and is not thread safe by itself. The app's private SamplingWorker confines every operation to one serial utility queue; only value snapshots cross back to the main thread.
- `GlimpseApp.MonitoringStore` owns the main-thread display state, persisted settings, timer lifecycle, and sleep/power notifications. Old results from replaced configurations are discarded.
- `StatusController` renders a single AppKit status item and presents the SwiftUI status panel. `SettingsView` edits settings through the store. No web runtime or external frameworks are bundled.

The default icon collects CPU, memory and download. The optional bandwidth block also demands upload. Opening status or settings temporarily demands all supported metrics. CPU and network read at the selected cadence; memory caches for 2 seconds, battery for 10, disk capacity for 30 and thermal state for 5. Low Power Mode imposes a 5-second minimum cadence. Sampling pauses during system sleep and rate baselines are reset before wake sampling. Settings changes preserve elapsed-time rate calculations; a newly selected interface begins with an unavailable baseline reading.

## What the numbers mean

- CPU: busy tick deltas divided by total tick deltas across the machine; normalized 0–100%, not per-core percentages added together.
- Memory: active + wired + compressor physical pages divided by physical RAM. Inactive cache is excluded. This is explicitly labelled usage, not memory pressure; Activity Monitor's category accounting is different. Absolute used/total capacities appear in detail.
- Network: 64-bit native interface-counter deltas divided by measured monotonic elapsed time. Automatic selection prefers the primary active physical interface, with an active physical fallback. IPv4 and IPv6 primary metadata are considered. A single explicitly selected tunnel is allowed. Physical and tunnel counters are never summed. Interface and read failures reset the baseline rather than creating a spike.
- Disk: root volume total minus Foundation available capacity; no summing of APFS volumes. This is capacity, not disk I/O throughput.
- Battery: IOKit internal battery current/max capacity, with charging/power-source status. A desktop without a battery is unavailable, not 0%.
- Thermal: the supported system thermal-state ordinal, displayed as Nominal/Fair/Serious/Critical. No estimated Celsius temperature or fan RPM is shown.

Bandwidth units are decimal B/s, KB/s, MB/s, etc., or decimal bits/s when selected. The default full-height network ceiling is 12.5 MB/s (100 Mb/s). That is a display scale, not measured link capacity. Percentage fill and threshold colours do not diagnose hardware health.

History is bounded to five minutes and at most 600 points per metric. Cached readings keep their collection timestamps and are not appended repeatedly. Unavailable samples and periods where a previously collected metric is no longer demanded break the graph. Closing the panel does not keep panel-only collectors running.

## Evidence and limits

Current evidence on the Apple silicon development Mac:

- Core arithmetic, settings migration/repair, history bounds/gaps, native route parsing/64-bit counters, interface policy, failure recovery, demand and cache behaviour have automated tests.
- The full suite currently passes 20 tests (12 core, including threshold-boundary regressions, and 8 native-reader tests).
- A live integration test and terminal diagnostic exercise actual CPU, VM, network, battery, disk and thermal readers without a privileged helper.
- A universal release build contains native arm64 and x86_64 slices. Both declare macOS 12.0 minimum deployment. The local ad-hoc bundle signature verifies. Xcode warns that x86_64 is deprecated on the development SDK; this does not establish older Intel runtime support.

Not verified: macOS 12 runtime, Intel hardware runtime, live VPN/physical-interface transitions, actual system sleep/wake, VoiceOver/keyboard/appearance/crowded-menu-bar behaviour, eight-hour stability, and release performance budgets. Computer-use inspection could not start because its Node runtime was unavailable. Successful compilation and native-reader tests do not prove these UI and hardware behaviours.

The proposed CPU/RSS/energy budgets in the design are still acceptance targets. Source-derived architecture choices are not performance measurements. There is no public notarized release, updater, App Store validation, sensor-temperature implementation, import/export UI, or disk-I/O meter yet. Track these investigations in the [GitHub project](https://github.com/users/nairdaleo/projects/10).
