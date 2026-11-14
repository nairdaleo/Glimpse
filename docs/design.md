# Glimpse design

Date: 2026-11-13

Status: first native development implementation; release validation remains open

License: MIT, selected by the project owner

Name: Glimpse is a working name

## Intent

Provide useful system status in as little macOS menu-bar space as possible, while letting each user choose the information they care about. Clicking the compact icon reveals detailed status. Optional persistent information blocks expose selected numbers without requiring a click.

The motivation is to replace the familiar utility of MenuMeters without depending on abandoned software. iGlance was studied as reference material, not adopted as an implementation base. A first development app now implements the core experience; performance and release compatibility remain unverified.

## Requirements and proposed choices

The owner requested a fully open-source app, a small configurable icon, colour and fill driven by chosen parameters, optional extra blocks including upload/download bandwidth, and detailed information on click. The owner also requested the oldest practical macOS support without sacrificing performance, and chose MIT.

Three continuous columns, the initial defaults, the API choices, refresh rates, performance budgets, and release distribution below are engineering proposals. They remain adjustable after the first experiments. The Tailscale nine-dot grid is a size reference, not artwork to copy.

## Approaches considered

| Approach | Benefit | Cost | Assessment |
| --- | --- | --- | --- |
| Continue iGlance | Existing settings, metrics, and UI | Older multi-tool dependency setup; separate status items; network polling needs replacement; hardware support unverified; GPL obligations for derived code | Viable maintenance project, less direct fit for the requested product |
| Fresh native application | Compact display and shared sampling designed together; control over minimum OS and dependencies | Monitoring accuracy, settings, and release infrastructure must be built and tested | Recommended basis for this proposal |
| Broad dashboard with many permanent meters | Lots of information visible immediately | Competes with the primary requirement to save menu-bar space | Keep detail in the click-open panel and make persistent blocks optional |

The owner authorized implementation of the independent native application on 2026-11-13. See [development notes](development.md) for current capabilities and validation limits.

## Compact icon and optional blocks

Default to one square NSStatusItem containing three slim columns within an approximately 16–18 point drawing area. The surrounding click target follows the system menu-bar dimensions. Exact geometry must be checked at native size on Retina and non-Retina displays, with light/dark appearances and crowded/notched menu bars.

After trying the first version, the owner requested flexible meter count, size, and drag organization. Settings now allow one to eight meters, a horizontal width scale of 0.75–1.5, and drag-to-reorder while preserving each meter's identity/configuration. The default remains three. A single composed image centers meter tracks and both bandwidth rows together, replacing NSButton's separate multiline title layout that clipped and offset the first version.

Each column has a selected metric, scale, base colour, and optional threshold colours. Base and graph colours use the standard macOS colour picker, alongside suggested mint, blue, purple, orange and pink swatches. Custom colours persist as bounded sRGB components; legacy preset strings retain their meaning. Fill height encodes magnitude independently of colour. Column assignment and order are configurable. The proposed first-run assignment is CPU usage, memory usage, and download rate; upload remains visible in the detailed panel and can replace any column. Defaults must be assessed in the readability experiment.

Use continuous fill initially; a three-dot segmented style can be compared in the experiment but is not a second required rendering mode. An unavailable reading has a visually distinct neutral state, never a fabricated zero. A zero value retains a visible track. Threshold transitions use a small deadband or short smoothing window to reduce flicker without concealing sustained changes.

Optional numeric blocks can show bandwidth or selected percentages. The bandwidth block offers two labelled rows, for example `↑ 240 KB/s` and `↓ 12 MB/s`, with explicit byte units and a bits/second option. Use monospaced digits and a reserved width so traffic changes do not move neighbouring items. Define formatting and maximum widths for large values. Begin with blocks inside one status item to avoid extra inter-item spacing. Independently draggable status items are a later option if users need that control.

The fixed 80-point bandwidth reservation left excessive trailing space in real use. The renderer now measures the active units and reserves a four-character numeric field (`999` or `99.9`), expanding for any longer formatter output. Digit changes within a unit remain stable without a large empty tail. Unit changes can resize the widget slightly.

The combined Upload / Download gauge fills upward from the center for upload and downward for download. Each half uses the network ceiling independently, its own colour and threshold latch, and a distinct missing-reading marker. Equal traffic fills both halves instead of cancelling into a net value. This ColumnConfiguration display mode demands the two real scalar metrics; it creates no synthetic combined reading. Existing layouts retain individual meters until the user selects the new mode.

A metric's high value is not automatically a problem: CPU activity can be intentional, disk usage reflects capacity, and low battery reverses the usual warning direction. Threshold configuration must include direction and units. Memory fullness must not be described as memory pressure; recoverable caches and compression make that interpretation misleading.

## Click-open detailed status

Clicking the icon toggles a live, anchored card grid with selected CPU, memory, network, battery, disk capacity and thermal panels. It no longer repeats a separate menu-bar summary above the cards. Provide short history graphs where repeated sampling is useful, particularly CPU and upload/download. A gear settings action and Quit remain easy to find.

Opening the panel does not reread every metric independently. It observes the same timestamped snapshots as the icon and optional blocks. Additional panel-only collectors start while needed and stop when the panel closes. Historical graphs represent collected samples only; missing periods are gaps, not zeroes or interpolated data. Keep at most five minutes of recent data in bounded memory initially. History begins when the app or collector starts and is not persisted to disk.

The click-open panel is called Detailed View in settings. Its cards are arranged/removed only in the settings organizer, using drag/drop or keyboard-accessible ordering controls. Both organizers use native drag previews, fade the source tile, and mark the destination edge with a blue insertion line. The left half inserts before a tile; the right half inserts after it. Only a completed drop saves the new order; Escape or dropping outside leaves it unchanged. Clicking a dropdown card opens its settings editor; selecting an organizer tile edits the same card. The + Add panel menu creates a selected card for immediate configuration, including repeated network metrics on separate interfaces. Cards have stable UUIDs. A single trash action removes a card; + Add panel creates a new configurable card. There is no separate hidden-card collection. There are at most 32 cards. Removing a card does not remove its menu-bar meter; collection stops only when neither display requires it. The gear button retains an accessible label and Command-comma shortcut.

The panel grid has one-to-eight cards per row, a shared card width of 120–240 points, and individual Compact/Regular/Large sizes, graph colours and history visibility. Row height follows its tallest card. More columns make the popup wider and shorter; fewer columns make it narrower and taller. StatusPanelLayout computes the size, capped to the active screen; scrolling preserves the requested grid instead of silently wrapping to fewer columns. Extra unused columns are not reserved when fewer cards are visible.

Keyboard activation, Escape to dismiss, VoiceOver labels, and readable values are required. Colour is never the only status cue. Expose stale and unsupported readings explicitly. Relaunching the app should bring settings or status forward even if its menu-bar item is crowded out.

## Data collection and accuracy

Use native macOS counters, with small testable readers separated from display formatting. Avoid shell commands and subprocess polling. A single scheduler samples required collectors in the background; AppKit updates happen on the main thread. The renderer consumes immutable snapshots containing value, unit, monotonic timestamp, and availability state. A reader failing must not prevent the remaining metrics or settings from working.

| Metric | Initial approach | Accuracy rule |
| --- | --- | --- |
| CPU | Mach host CPU tick counters | Delta between samples; 0–100% normalized across the whole machine; establish a baseline first |
| Memory | Mach VM statistics and physical memory | Document categories and match the chosen definition; distinguish used memory from pressure; validate against Activity Monitor with tolerance |
| Network | Native per-interface byte counters; evaluate 64-bit routing/sysctl counters | Bytes delta divided by measured monotonic elapsed time; baseline separately for every interface identity |
| Battery | IOKit power-source information | Distinguish absent battery, charging, unavailable data, and actual 0% |
| Disk capacity | Foundation volume capacity information | Identify selected volume and exact free/available definition; do not add APFS volumes together |

Memory and disk byte sizes follow the Display setting *Capacity units*: SI (powers of 1000, GB, default) or IEC (powers of 1024, GiB). Disk detail leads with free space ("Free: 61.0 GB · …"), shown on compact cards too. The earlier "combine compact pair" toggle was removed; compact cards always stack as separate half-slots.
| Thermal state | ProcessInfo thermalState | Label nominal/fair/serious/critical as system thermal state, not a Celsius estimate |

Network policy is visible and configurable: default to the active physical interface; allow independent explicit interface selection for every network column and Detailed View card. The persistent numeric bandwidth block has its own interface choice. One shared native counter read supplies independent baselines for each demanded physical or tunnel interface; Auto and explicit selections of the same interface share one calculation. History is keyed by actual interface identity, so different devices and recreated interfaces do not join into a single graph. Interface details show native interface type, local IPv4/IPv6 addresses and service-scoped DNS servers/search domains. These are resolver settings, not visited destinations. Metadata is collected only while relevant UI is visible and refreshed at most every ten seconds, except when the interface inventory changes. Do not add physical and VPN/tunnel counters together as though they are independent traffic. Automatic physical interface selection, IPv6-only connectivity, Tailscale/VPN coexistence, Wi-Fi/Ethernet switching, interface recreation, and simultaneous physical connections require validation. The panel names the interface being measured and what is excluded. Interface changes and counter resets establish new baselines without spikes. Prefer 64-bit counters and handle rollover where a platform path returns narrower values.

Percentage metrics have a natural 0–100% scale. Bandwidth columns initially use a configurable fixed ceiling with visible units and sensible presets. A saturated column remains full while the exact value stays available. Adaptive bandwidth scaling is deferred because changing the scale can make identical heights mean different speeds.

Temperature and fan RPM are later capabilities requiring separate hardware and API investigation. Do not assume iGlance's sensor keys work on Apple silicon. Missing sensors never block launch. No fan-control feature is planned.

## Low overhead

Proposed default cadence: CPU and network every second; memory every two seconds; disk capacity every 30 seconds; battery and thermal changes use notifications where possible, with limited fallback reads. Users may choose slower refresh. Sample only metrics required by visible content or an open panel. Use timer tolerance, bounded histories, and no continuous animation loop. Suspend sampling during sleep and re-baseline rate counters after wake. Reduce cadence in Low Power Mode and avoid persistent per-sample logs.

Initial acceptance budgets, not measurements: under 0.5% of one CPU core on average while idle with default monitoring, under 50 MiB resident memory after warm-up, and no sustained memory growth over an eight-hour run. Record CPU normalization and Instruments/Activity Monitor measurement method so results are comparable. Measure app size, wakeups, energy impact, and panel-open cost as well. Adjust budgets with documented evidence rather than claiming them before measurement.

## macOS compatibility and implementation

Initial deployment target: macOS 12 Monterey. Release architecture goal: universal arm64 and x86_64. Selected development toolchain: Xcode 27.2. Apple lists macOS 12 as its minimum supported deployment target; the local iGlance build attempt confirms that its 10.12 target is rejected.

Supporting older runtime versions does not require using old polling designs. AppKit NSStatusItem and the proposed native sampling approaches allow a small, efficient application. Use Swift for the app, AppKit for status-item drawing and presentation, and SwiftUI for settings only where APIs meet the deployment target. Avoid making MenuBarExtra (macOS 13+) or SwiftData (macOS 14+) core dependencies. Prefer UserDefaults with a versioned settings representation. No database, web runtime, CocoaPods, or Carthage is proposed. SwiftPM now pins Sparkle 2.9.6 for signed updates, an owner-requested capability.

Use availability checks for newer optional features. Start at login uses SMAppService on macOS 13+ and a bundled short-lived SMLoginItemSetEnabled helper on Monterey. The owner requested a settings toggle on both. Report approval/errors and the legacy status-query limitation honestly. Neither path enables itself automatically.

macOS 12 is a toolchain-based initial floor, not the oldest technically conceivable runtime. Before the first release, evaluate whether a compatible older Xcode can target macOS 11 or earlier without regressions or an unsustainable second build path. Lower the floor only with a reproducible build and real runtime testing. Do not advertise any OS/architecture combination as verified until tested. Document separately the OS needed to run the app and the OS needed to run Xcode. Supporting an old macOS version is not a claim that Apple still provides security updates for it.

## Settings, privacy, and distribution

Settings cover column assignments/order, scales, units, threshold direction/colours, persistent blocks, interface selection, and refresh cadence. Save locally with defaults for missing keys and validation for invalid values. Provide a reset action. Import/export can follow after the first usable version.

No account, cloud synchronization, advertising, analytics, or remote metric uploads are planned. Short history stays in memory. Diagnostics, if added, require an explicit export and must avoid credentials and unnecessary network identifiers. The first implementation should run without a privileged helper; test actual API access before promising sandbox or App Store compatibility.

Initial direct distribution uses signed and notarized GitHub releases, with complete source and reproducible build instructions. Sparkle manages opt-in checks/downloads and signature-verified installation; only its public key and feed configuration are committed. No public update archive is published yet. Homebrew can follow once stable. Document quit, login-item removal, and ordinary app deletion so removing the app never depends on a functioning menu-bar button.

The owner also requested a fully free Mac App Store edition, with optional tips and reviews. It needs a separate sandboxed build excluding Sparkle, store-managed updates, validated native counter permissions, StoreKit developer tips, and Apple's review API. These are release work; no features will require payment or a review. See [updates and distribution](updates.md).

## Verification and first milestones

1. Compare column and segmented sketches at actual menu-bar size, including colour-vision and monochrome checks; validate the detailed-panel hierarchy.
2. Probe native CPU, memory, and network readers on current Apple silicon; verify elapsed-time calculations and interface selection.
3. Build the compact icon, shared snapshots, click-open detailed panel, and optional fixed-width bandwidth block.
4. Add settings and metrics with graceful unavailability, then verify native Intel and macOS 12 operation.
5. Profile idle and loaded operation, eight-hour memory stability, sleep/wake, and crowded menu-bar behaviour before a signed release.

Tests should cover counter resets, first samples, elapsed-time variation, interface switching, formatting boundaries, missing hardware, settings validation, and bounded history. Verify readings against independent system tools under controlled workloads; exact simultaneous matches are not expected from differently timed samples. Avoid tests that merely mirror drawing implementation.

Remaining decisions for the implementation stage: final name and visual styling, exact memory accounting and pressure reporting, fixed bandwidth presets, API permissions, and the practical older-toolchain experiment. These are tracked investigations, not claims of completed work.

## Sources

- [Apple: Xcode deployment targets](https://developer.apple.com/support/xcode/)
- [Apple: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [Apple: CPU counters](https://developer.apple.com/documentation/kernel/host_cpu_load_info_t)
- [Apple: interface counter fields](https://developer.apple.com/documentation/kernel/if_data)
- [Apple: thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- [iGlance assessment and source references](iglance-assessment.md)
- [License rationale](licensing.md)
