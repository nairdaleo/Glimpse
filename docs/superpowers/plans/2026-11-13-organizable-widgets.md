# Organizable widgets implementation plan

> User requested this change after trying the first app. Continue directly with implementation and focused subagents; no new product decisions are blocked.

**Goal:** Drag-to-organize settings and dropdown cards, one to eight configurable meters, adjustable meter width, gear-only settings action, and a centered unclipped menu-bar widget.

**Architecture:** Keep macOS 12 and the native sampler. Persist column identities, validated size and ordered visible panels in AppSettings. Use native SwiftUI onDrag/onDrop for macOS 12, with keyboard-accessible move/add/remove alternatives. Draw the entire menu-bar graphic, including both bandwidth rows, inside a single image centered in NSStatusBarButton.

**Spec:** docs/design.md plus owner requests on 2026-11-13.

## Global constraints and review focus

- MIT, macOS 12, native arm64/x86_64; Sparkle 2.9.6 is the sole pinned dependency added for owner-requested signed updates.
- Preserve saved three-column configurations, colours and thresholds. Missing new keys get defaults.
- Keep one to eight columns; zero cannot make the app unreachable. Column scale 0.75...1.5 changes horizontal meter width/gap, retaining a 16-point vertical track.
- Visible dropdown panels are an ordered unique subset of MetricID; an empty subset is valid. Hiding never removes an icon meter or prevents restoring the panel.
- Drag reorders preserve each column's configuration/identity. Cross-list/external drags must not silently corrupt ordering. A drag ending outside a target must not move an item.
- Hidden, unneeded panels are not sampled. Settings can still populate the network-interface picker even with all network displays hidden.
- Both bandwidth rows and meter tracks share the same vertical center; status button has no multiline title. Labelled gear remains accessible through help/VoiceOver and Command-comma.

## Tasks

1. Core/settings and sampler: add stable UUID column identities, scale, ordered panelMetrics, validation/migration and bounds. Add tested move/add/remove helpers and tests for invalid drags, one/eight limits, hidden panels and sampler demand. NativeSampler adds configurationVisible default false to preserve tests/CLI and force only network inventory when settings are open.
2. Settings and dropdown: organize columns in a horizontal shelf with real drag/drop, add/remove and keyboard alternatives, select a column to edit colours/thresholds. Panels tab restores/hides/reorders dropdown cards; dropdown supports direct card reordering/hiding. Gear-only settings action. Own UI selection by identity and tolerate removed selections/bindings during async SwiftUI updates.
3. Renderer/integration: use dynamic column count and width, compose icon and bandwidth into one vertically centered image. Resize threshold latch storage. Pass independent detail/configuration visibility to the sampler. Add geometry/render tests for one/eight columns, optional bandwidth, and row clipping. Add a development render-check command if needed for raster inspection without desktop automation.
4. Verify all tests, universal compilation/signature, reader diagnostics, drawing artifact and independent review. Update docs and rebuild/relaunch the app; commit/push verified code. Record limits of direct macOS drag interaction testing if computer-use remains unavailable.

## Added scope and result

During implementation the owner requested automatic updates and start-at-login settings, authorized Tasty Jam signing, and chose a fully free product with optional tips/reviews and a future Mac App Store edition. The direct build now embeds Sparkle and its public feed/signing configuration; the private Ed25519 key remains in the login Keychain. Modern login registration and a Monterey helper are wired but not automatically enabled. The available Tasty Jam Apple Development identity signs local builds; distribution still needs Developer ID/notarization.

The full 32-test suite passes (19 core, 10 native-reader, 3 widget-render tests). The universal app and login helper compile, nested signatures verify, and an offscreen rendered artifact confirms aligned meter/text geometry. Independent review approves the implementation after lifecycle refresh and signing-account documentation fixes. Live drag/accessibility interactions, actual login/logout, installation of a signed update, Monterey/Intel runtime and store sandbox validation remain explicit release checks. The appcast intentionally has no public downloadable binary yet.
