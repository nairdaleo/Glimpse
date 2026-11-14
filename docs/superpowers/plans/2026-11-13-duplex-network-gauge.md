# Compact network readout and duplex gauge

**Goal:** Remove excessive bandwidth trailing space and add one meter whose upper half fills from the middle for upload and lower half fills downward for download.

**Architecture:** Keep real MetricID readings scalar and independent. Add an isCombinedNetwork display mode to ColumnConfiguration, with requiredMetrics returning upload/download and a second configurable colour. A combined meter consumes the existing two readers, not an invented net-traffic scalar. Render each half independently, including unavailable/idle states. Existing individual network meters and panels keep their meaning.

**Constraints:** macOS 12, stable column identity, legacy Codable defaults, one-to-eight bounds, MIT, no new dependencies. Keep moderate width stability using a four-character numeric budget for the current units instead of the old 80-point text reservation. No changes to user settings except explicit edits.

1. Add first-failing tests for compact text measurement, duplex fill direction/zero/saturation/missing halves, settings migration and both-direction demand with panels hidden.
2. Core/sampler: ColumnConfiguration isCombinedNetwork default false, secondaryColour default blue, displayTitle and requiredMetrics; when combined normalize backing metric to download and validate thresholds in B/s. Preserve these fields through reorder/encoding. Demand upload and download for the special meter.
3. Settings: add Upload / Download entry to Add meter and selection; configure upload/down colours separately and explain center-out direction. Summary/tooltips show both exact rates. Panels remain their independent scalar readings.
4. Renderer: dynamically budget text width, center-out halves with independent threshold latches, shared center marker, normal idle and half-specific unavailable markers. Test and inspect rendered artifact.
5. Run full suite and universal development-sign build, independent review, update docs, commit/push and relaunch.

## Additional owner correction

The owner refined dropdown organization: rearrangement/hiding belongs only in settings. Dropdown cards only open their own settings when clicked. Settings gains a card organizer matching the meter shelf, one-to-eight cards per row, global card width and per-card compact/regular/large size, colour and history visibility. The live dropdown sizes to the selected grid, using horizontal/vertical scrolling only when screen bounds prevent the requested dimensions. No unnecessary empty columns are reserved when fewer cards are visible than the selected maximum.

Core persists panelColumns, panelCardWidth and per-metric PanelAppearance with compatible defaults. StatusPanelLayout centralizes row maxima and content sizing. StatusController recalculates popover content size as settings change and passes the available screen size. A card click opens SettingsView on the requested panel; a gear click retains general settings navigation. Regression coverage compares one-column tall versus eight-column wide layouts, card sizes, empty panels and screen bounds.

## Verification result

All 48 tests pass (28 Core, 11 native-reader, 9 app layout/render tests). The universal development-signed bundle passes nested signature verification, and its native diagnostic reads current system values. The rendered duplex artifact shows upload above and download below the center with a compact numeric readout. Independent review found no actionable issues. Direct UI inspection was retried through the newly available computer-use tool but its Node runtime still failed to start, so live drag/drop, popup resizing/scrolling and accessibility remain manual checks. Intel and Monterey runtime limitations are unchanged.
