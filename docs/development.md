# Development and validation

## Build and run

The current verified development toolchain is Xcode 27.2. Select it with `xcode-select` as appropriate for your installation. SwiftPM resolves the pinned Sparkle 2.10.1 framework; no other package manager is required. The package manifest uses Swift tools 5.9; older developer toolchains have not been tested. The app deployment target is macOS 12, which is separate from the macOS version needed to run Xcode.

```bash
swift test
./scripts/build-app.sh
open build/Glimpse.app
```

The app runs in the menu bar without a Dock icon. Clicking its icon toggles detailed status. Settings has a drag-to-organize shelf of one to eight meters, width scale, assignment/order, palette, optional threshold colours/direction, monochrome meters, bandwidth readout/units, interface, refresh and reset. Add or select **Upload / Download** for a two-colour meter: upper half upload, lower half download. Exact rates remain independent in the tooltip and detail panels.

The Detailed View tab has a + Add panel menu. Panels are selected for immediate editing and dragged into order, removed only in the settings organizer. Up to 32 panels can be saved; repeated metrics have independent UUIDs and configurations. Both organizers show a drag preview, faded source and blue insertion marker; dropping on the left/right half inserts before/after. Canceling does not save a move. Meters and graph colours have the native colour picker and suggested swatches. Choose 1–8 cards per row and a shared card width; each card has size, graph colour and history options. Clicking a dropdown card opens its editor. The popup sizes to its row maxima and column widths, with scrolling when constrained by the screen. The gear opens settings, including opt-in login/update controls. Reopening the app opens settings. For a direct settings launch:

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

Start at login is configured in the General settings tab. **Remove Glimpse…** there uninstalls (login item off, optional settings removal, app to Trash, quit); manually, turn it off, quit via the status panel and move the app to the Trash. Remove any separately/manually added login item in macOS Login Items. Preferences remain in the `com.tastyjam.glimpse` defaults domain; remove them separately only if you want to reset saved choices. Update signing and distribution details are in [updates.md](updates.md).

## Reader diagnostic

```bash
build/Glimpse.app/Contents/MacOS/Glimpse --diagnose
```

This terminal mode reads all metrics twice, separated by 1.1 seconds to establish rate baselines. It prints current values and the measured interface without launching the menu-bar UI. It does not change settings, export private diagnostics, launch shell polling, or upload anything.

## Card render audit

```bash
build/Glimpse.app/Contents/MacOS/Glimpse --render-cards /path/to/folder
GLIMPSE_RENDER_ARTIFACTS=/path/to/folder swift test --filter MetricCardRenderingTests
```

`--render-cards` samples live readings for about five seconds, then writes PNGs of every saved panel at every card size (compact, regular, large vertical, large horizontal) in light and dark appearance. Use it to check readability with real data before shipping layout changes; the images contain local addresses, so keep them local. The test variant renders every metric and size with fixed sample data. SwiftUI squeezes or truncates content inside a card rather than drawing outside it, so these renders need a visual review; a pixel-margin check cannot detect cut-off text.

## Architecture

Modules, data flow, threading, editions and the build pipeline are described in [architecture.md](architecture.md).

### Sampling and demand details

The default icon collects CPU, memory and download. Each network meter and panel chooses Auto or its own interface; the optional numeric readout has a separate choice. NetworkHistory stores bounded histories by actual interface identity and direction. A single native counter read feeds all demanded interfaces, with Auto and explicit duplicates sharing one rate calculation. Interface type, local addresses and service-scoped DNS/search domains are cached for ten seconds while settings/network details are visible. No remote address lookup or visited-domain collector is implemented. Legacy global interface selections migrate into existing network meters/cards; explicit Auto choices remain independent in new settings. The optional bandwidth block also demands upload. Opening status demands only configured Detailed View panels; removed panels add no demand unless a meter needs the same metric. Opening settings permits network inventory enumeration for the picker without publishing hidden readings or creating rate baselines. CPU and network read at the selected cadence; memory caches for 2 seconds, battery for 10, disk capacity for 30 and thermal state for 5. Low Power Mode imposes a 5-second minimum cadence. Sampling pauses during system sleep and rate baselines are reset before wake sampling. Settings changes preserve elapsed-time rate calculations; a newly selected interface begins with an unavailable baseline reading.

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

## Secret scan before every push

`.githooks/pre-push` runs [betterleaks](https://betterleaks.com) on the commits being pushed and blocks the push if it finds a secret. `./setup.sh` installs betterleaks (after asking) and enables the hook; by hand:

```bash
brew install betterleaks
git config core.hooksPath .githooks
```

Without betterleaks installed the hook refuses to push rather than skipping the scan. Mark a false positive with a `betterleaks:allow` comment on its line, or list it in `.betterleaksignore`. CI also scans the full history with gitleaks on every push.
