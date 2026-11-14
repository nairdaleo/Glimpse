import SwiftUI
import GlimpseCore

struct SettingsView: View {
    private enum Tab: Hashable { case columns, panels, display, general }
    @ObservedObject var store: MonitoringStore
    @ObservedObject var services: LifecycleServices
    @State private var selectedColumnID: UUID? = nil
    @State private var selectedPanelID: UUID? = nil
    @State private var dropPreview: DropPreview? = nil
    @State private var selectedTab: Tab = .columns

    init(store: MonitoringStore, services: LifecycleServices, requestedPanel: UUID? = nil) {
        self.store = store
        self.services = services
        _selectedPanelID = State(initialValue: requestedPanel)
        _selectedTab = State(initialValue: requestedPanel == nil ? .columns : .panels)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make room for what matters.").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Your meters, in your order.").foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill").font(.system(size: 30)).foregroundColor(.accentColor)
            }.padding(.bottom, 6)
            TabView(selection: $selectedTab) {
                columnSettings.tabItem { Text("Columns") }.tag(Tab.columns)
                panelSettings.tabItem { Text("Detailed View") }.tag(Tab.panels)
                displaySettings.padding(20).tabItem { Text("Display & Network") }.tag(Tab.display)
                generalSettings.padding(20).tabItem { Text("General") }.tag(Tab.general)
            }
            HStack {
                Spacer()
                Button("Reset settings") { store.resetSettings() }
            }
        }.padding(22).frame(minWidth: 560, idealWidth: 590, minHeight: 570)
            .onAppear {
                services.refreshLoginStatus()
                store.setSettingsPreviewVisible(selectedTab == .panels)
            }
            .onChange(of: selectedTab) { tab in store.setSettingsPreviewVisible(tab == .panels) }
            .onDisappear { store.setSettingsPreviewVisible(false) }
    }

    private var selectedID: UUID? {
        selectedColumnID.flatMap { id in store.settings.columns.contains(where: { $0.id == id }) ? id : nil }
            ?? store.settings.columns.first?.id
    }

    private var columnSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Menu-bar meters").font(.headline)
                    Text("\(store.settings.columns.count) of 8").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        Button("Upload / Download") { addColumn(metric: .download, combined: true) }
                        ForEach(MetricID.allCases) { metric in
                            Button(metric.title) { addColumn(metric: metric) }
                        }
                    } label: { Label("Add meter", systemImage: "plus") }
                    .disabled(store.settings.columns.count >= 8)
                }
                Text("Drag either side of a meter to place it before or after. The blue line marks the drop position. Click to edit.")
                    .font(.caption).foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(Array(store.settings.columns.enumerated()), id: \.element.id) { index, column in
                            OrganizationTile(payload: .column(column.id), kind: .column, isSelected: selectedID == column.id, label: "Meter \(index + 1), \(column.displayTitle)", select: { selectedColumnID = column.id }, drop: { payload, edge in
                                completeDrop(payload, target: .column(column.id), edge: edge)
                            }) {
                                VStack(spacing: 7) {
                                    Image(systemName: "line.3.horizontal").font(.caption).foregroundColor(.secondary)
                                    if column.isCombinedNetwork {
                                        VStack(spacing: 1) {
                                            Rectangle().fill(Color(column.colour.nsColor))
                                            Rectangle().fill(Color(column.secondaryColour.nsColor))
                                        }.frame(width: 12, height: 28).cornerRadius(2)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2).fill(Color(column.colour.nsColor))
                                            .frame(width: 12, height: 28)
                                    }
                                    Text("\(index + 1) · \(column.displayTitle)").font(.caption)
                                        .multilineTextAlignment(.center).lineLimit(2)
                                        .frame(height: 30, alignment: .top)
                                }
                                .frame(width: 94, height: 84)
                                .background(selectedID == column.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedID == column.id ? Color.accentColor : Color.clear, lineWidth: 1.5))
                            }
                            .frame(width: 94, height: 84)
                        }
                    }.padding(2)
                }
                HStack {
                    Text("Meter width")
                    Slider(value: setting(\.columnScale), in: 0.75...1.5, step: 0.05)
                        .accessibilityLabel("Meter width")
                    Text("\(Int((store.settings.columnScale * 100).rounded()))%")
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                if let id = selectedID {
                    ColumnEditor(store: store, id: id)
                }
                Text("Fill shows magnitude. Optional warning colours use the metric’s own units. Memory usage is not memory pressure.")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(16)
        }
    }

    private func completeDrop(_ payload: OrganizationDragPayload, target: OrganizationDragPayload?, edge: OrganizationDropEdge) -> Bool {
        var changed = false
        store.change { settings in
            changed = OrganizationDrop.apply(payload, target: target, edge: edge, settings: &settings)
        }
        return changed
    }

    /// Runs the drop against a copy of the settings and reports where the
    /// dragged card would be placed, so the preview can draw a ghost there.
    private func destinationPreview(_ payload: OrganizationDragPayload?, _ edge: OrganizationDropEdge?, target: OrganizationDragPayload) -> DropPreview? {
        guard let payload, case .panel(let draggedID) = payload, let edge,
              case .panel(let targetID) = target else { return nil }
        var copy = store.settings
        guard OrganizationDrop.apply(payload, target: target, edge: edge, settings: &copy) else { return nil }
        let previewLayout = StatusPanelLayout(settings: copy, maximumSize: CGSize(width: 10000, height: 10000))
        return previewLayout.placements[draggedID].map { DropPreview(id: draggedID, rect: $0) }
    }

    private func addColumn(metric: MetricID, combined: Bool = false) {
        store.change { settings in
            guard let id = WidgetOrganization.addColumn(to: &settings, metric: metric) else { return }
            if combined, let index = settings.columns.firstIndex(where: { $0.id == id }) {
                settings.columns[index].isCombinedNetwork = true
                settings.columns[index].colour = .mint
                settings.columns[index].secondaryColour = .blue
            }
            selectedColumnID = id
        }
    }

    private var panelSettings: some View {
        let layout = StatusPanelLayout(settings: store.settings, maximumSize: CGSize(width: 10000, height: 10000))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Regular slots per row", selection: setting(\.panelColumns)) {
                        ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                    }.frame(width: 260)
                    Spacer()
                    Menu {
                        Button("Upload / Download") { addPanel(metric: .download, combined: true) }
                        ForEach(MetricID.allCases) { metric in
                            Button(metric.title) { addPanel(metric: metric) }
                        }
                    } label: { Label("Add panel", systemImage: "plus") }
                    .disabled(store.settings.panels.count >= 32)
                }
                HStack {
                    Text("Regular card width")
                    Slider(value: setting(\.panelCardWidth), in: 120...240, step: 4).accessibilityLabel("Card width")
                    Text("\(Int(store.settings.panelCardWidth)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                }
                Text("Detailed View preview").font(.headline)
                Text("Drag either side of a card to place it before or after. Click to edit. Compact cards share a regular slot; large cards use two slots.")
                    .font(.caption).foregroundColor(.secondary)
                if store.settings.panels.isEmpty {
                    Text("No panels yet. Use + Add panel to choose what to show.")
                        .font(.callout).foregroundColor(.secondary).padding(.vertical, 8)
                } else {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(store.settings.panels.enumerated()), id: \.element.id) { index, panel in
                                if let rect = layout.placements[panel.id] {
                                    OrganizationTile(payload: .panel(panel.id), kind: .panel, isSelected: selectedPanel?.id == panel.id,
                                                     label: "Panel \(index + 1), \(panel.displayTitle), \(panel.appearance.size.title)", select: { selectedPanelID = panel.id }, drop: { payload, edge in
                                        completeDrop(payload, target: .panel(panel.id), edge: edge)
                                    }, hover: { incoming, edge in
                                        let next = destinationPreview(incoming, edge, target: .panel(panel.id))
                                        if dropPreview != next { dropPreview = next }
                                    }) {
                                        MetricCardContent(panel: panel, snapshot: store.snapshot, history: store.history,
                                                          networkHistory: store.networkHistory, settings: store.settings,
                                                          width: rect.width, height: rect.height)
                                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedPanel?.id == panel.id ? Color.accentColor : Color.clear, lineWidth: 2))
                                    }.frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY)
                                }
                            }
                        }.frame(width: layout.gridWidth, height: layout.gridHeight, alignment: .topLeading).padding(2)
                            .overlay {
                                if let dropPreview {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color.accentColor.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3])))
                                        .frame(width: dropPreview.rect.width, height: dropPreview.rect.height)
                                        .offset(x: dropPreview.rect.minX, y: dropPreview.rect.minY)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                    }.frame(height: min(360, layout.gridHeight + 4))
                }
                if let panel = selectedPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(panel.displayTitle) panel").font(.headline)
                            Spacer()
                            Button("Move earlier") { movePanel(panel.id, offset: -1) }
                                .disabled(store.settings.panels.first?.id == panel.id)
                            Button("Move later") { movePanel(panel.id, offset: 1) }
                                .disabled(store.settings.panels.last?.id == panel.id)
                            Button { store.change { _ = WidgetOrganization.removePanel(from: &$0, id: panel.id) } } label: {
                                Image(systemName: "trash")
                            }.help("Remove this panel configuration")
                                .accessibilityLabel("Remove \(panel.displayTitle) panel")
                        }.font(.caption)
                        PanelEditor(store: store, id: panel.id)
                    }.padding(12).background(Color.primary.opacity(0.04)).cornerRadius(8)
                }

            }.padding(16)
        }
    }

    private var selectedPanel: PanelConfiguration? {
        store.settings.panels.first { $0.id == selectedPanelID } ?? store.settings.panels.first
    }

    private func addPanel(metric: MetricID, combined: Bool = false) {
        store.change { settings in
            selectedPanelID = WidgetOrganization.addPanel(to: &settings, metric: metric, isCombinedNetwork: combined)
        }
    }

    private func movePanel(_ id: UUID, offset: Int) {
        store.change { settings in
            guard let index = settings.panels.firstIndex(where: { $0.id == id }) else { return }
            let destination = index + offset
            guard settings.panels.indices.contains(destination) else { return }
            let target = offset < 0 ? settings.panels[destination].id : settings.panels.dropFirst(destination + 1).first?.id
            _ = WidgetOrganization.movePanel(in: &settings, id: id, before: target)
        }
    }

    private var displaySettings: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Show upload and download speeds beside the icon", isOn: setting(\.showBandwidth))
            Toggle("Use bits per second for bandwidth", isOn: setting(\.bandwidthInBits))
            Toggle("Use monochrome meter columns", isOn: setting(\.monochrome))
            Divider()
            Picker("Capacity units", selection: setting(\.capacityUnits)) {
                ForEach(CapacityUnits.allCases) { Text($0.title).tag($0) }
            }
            Picker("Bandwidth units", selection: setting(\.bandwidthUnits)) {
                ForEach(CapacityUnits.allCases) { Text($0 == .si ? "SI (MB/s)" : "IEC (MiB/s)").tag($0) }
            }
            Text("Capacity units apply to memory and disk sizes; bandwidth units to upload/download rates and the network ceiling. SI uses powers of 1000, IEC powers of 1024.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Network columns full at").font(.headline)
            ForEach([(\AppSettings.networkCeiling, "Download"), (\AppSettings.uploadCeiling, "Upload")], id: \.1) { keyPath, title in
                HStack {
                    let bits = store.settings.bandwidthInBits
                    let units = store.settings.bandwidthUnits
                    let unit = BandwidthCeilingInput.unit(bits: bits, units: units)
                    Text(title).frame(width: 70, alignment: .leading)
                    DecimalField(placeholder: unit, value: Binding(get: { BandwidthCeilingInput.displayValue(bytesPerSecond: store.settings[keyPath: keyPath], bits: bits, units: units) }, set: { value in store.change { $0[keyPath: keyPath] = BandwidthCeilingInput.bytesPerSecond(displayValue: value, bits: bits, units: units) } }))
                        .id("\(title)\(bits)\(units.rawValue)")
                        .frame(width: 80)
                    Text("\(unit) (\(bits ? "bits" : "bytes"))").foregroundColor(.secondary)
                }
            }
            NetworkInterfacePicker(title: "Bandwidth readout interface", selection: setting(\.networkInterface), snapshot: store.snapshot)
            Text("Each network meter and detail panel has its own interface choice. Auto follows one active physical interface; counters from different interfaces are never added together.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Network interfaces").font(.headline)
            Text("Local addresses and interface-specific DNS configuration. DNS servers and search domains are not a list of visited websites.")
                .font(.caption).foregroundColor(.secondary)
            ForEach(store.snapshot.interfaceDetails, id: \.name) { info in
                DisclosureGroup("\(info.name) · \(info.kind)") {
                    NetworkInterfaceDetails(info: info).padding(.top, 6)
                }
            }
            if store.snapshot.interfaceDetails.isEmpty {
                Text("Loading network interfaces…").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    }

    private var generalSettings: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Start at login", isOn: Binding(get: { services.loginEnabled }, set: { services.setLoginEnabled($0) }))
            Text(services.loginStatus).font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Automatically check for updates", isOn: Binding(get: { services.automaticChecks }, set: { services.setAutomaticChecks($0) }))
                .disabled(!services.updateConfigured)
            Toggle("Automatically download updates", isOn: Binding(get: { services.automaticDownloads }, set: { services.setAutomaticDownloads($0) }))
                .disabled(!services.automaticChecks || !services.updateConfigured)
            HStack(alignment: .top) {
                Button("Check for Updates…") { services.checkForUpdates() }.disabled(!services.canCheckForUpdates)
                Text(services.updateStatus).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Picker("Refresh", selection: setting(\.refreshInterval)) {
                Text("Every second").tag(1.0)
                Text("Every 2 seconds").tag(2.0)
                Text("Every 5 seconds").tag(5.0)
                Text("Every 10 seconds").tag(10.0)
                Text("Every 30 seconds").tag(30.0)
                Text("Every minute").tag(60.0)
            }
            Text("Low Power Mode refreshes no faster than every 5 seconds. Disk and battery readings update less often. Sampling pauses while your Mac sleeps.")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            Text("Local by design").font(.headline)
            Text("Settings stay on this Mac. Recent measurements are kept in memory and disappear when you quit. There is no account or analytics service.")
                .font(.callout).foregroundColor(.secondary)
            Text("To remove Glimpse, turn off Start at login, quit, and move the app to the Trash.")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Text("License: MIT").font(.caption).foregroundColor(.secondary)
                Spacer()
                Link(destination: URL(string: "https://github.com/nairdaleo/Glimpse")!) {
                    Image("GitHubMark", bundle: .module)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Source code and issue tracker on GitHub")
                .accessibilityLabel("Glimpse on GitHub")
            }
            Spacer()
        }
        }
    }

    private var interfaceNames: [String] {
        Array(Set(store.snapshot.availableInterfaces + [store.settings.networkInterface].compactMap { $0 })).sorted()
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.change { $0[keyPath: keyPath] = value } })
    }

    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

/// Where a dragged panel card would land if dropped now, computed by running
/// the real layout on a simulated drop so the ghost always matches the outcome.
private struct DropPreview: Equatable {
    let id: UUID
    let rect: CGRect
}

/// Decimal text field that can be cleared while editing. Keystrokes that
/// parse update the value immediately; an empty or invalid draft keeps the
/// stored value and is replaced by the formatted value when editing ends.
private struct DecimalField: View {
    let placeholder: String
    @Binding var value: Double
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { draft ?? SettingsView.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)" },
            set: { text in
                draft = text
                if let number = SettingsView.numberFormatter.number(from: text) {
                    value = number.doubleValue
                }
            }))
            .focused($focused)
            .onChange(of: focused) { if !$0 { draft = nil } }
    }
}

private struct ColumnEditor: View {
    @ObservedObject var store: MonitoringStore
    let id: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meter \((index ?? 0) + 1)").font(.headline)
                    Text(configuration.displayTitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button("Move left") { move(offset: -1) }.font(.caption)
                    .disabled(index == nil || index == 0)
                Button("Move right") { move(offset: 1) }.font(.caption)
                    .disabled(index == nil || index == store.settings.columns.count - 1)
                Button("Remove") { store.change { _ = WidgetOrganization.removeColumn(from: &$0, id: id) } }
                    .font(.caption).disabled(store.settings.columns.count <= 1)
                    .accessibilityLabel("Remove selected meter")
            }
            HStack {
                Picker("Metric", selection: Binding(get: { configuration.isCombinedNetwork ? "combinedNetwork" : configuration.metric.rawValue }, set: { choice in
                    let combined = choice == "combinedNetwork"
                    guard let metric = combined ? MetricID.download : MetricID(rawValue: choice) else { return }
                    edit { column in
                        guard column.isCombinedNetwork != combined || (!combined && column.metric != metric) else { return }
                        if combined && !column.isCombinedNetwork {
                            column.secondaryColour = column.colour == .blue ? .mint : .blue
                        }
                        column.metric = metric
                        column.isCombinedNetwork = combined
                        column.warningThreshold = nil
                        column.criticalThreshold = nil
                        column.downloadWarningThreshold = nil
                        column.downloadCriticalThreshold = nil
                        column.thresholdDirection = .above
                        column.colourBands = nil
                    }
                })) {
                    Text("Upload / Download").tag("combinedNetwork")
                    ForEach(MetricID.allCases) { Text($0.title).tag($0.rawValue) }
                }
                // Battery shows its colour inside the Colours section instead.
                if !configuration.isCombinedNetwork && configuration.metric != .battery {
                    colourPicker("Colour", keyPath: \.colour).fixedSize()
                }
            }
            if configuration.isNetwork {
                NetworkInterfacePicker(selection: Binding(get: { configuration.networkInterface }, set: { value in edit { $0.networkInterface = value } }), snapshot: store.snapshot)
                SelectedInterfaceDetails(selection: configuration.networkInterface, snapshot: store.snapshot)
            }
            if configuration.isCombinedNetwork {
                VStack(alignment: .leading) {
                    colourPicker("Upload", keyPath: \.colour)
                    colourPicker("Download", keyPath: \.secondaryColour)
                }
                Text("Upload fills above the center; download fills below.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if configuration.metric == .battery && !configuration.isCombinedNetwork {
                colourBandsEditor
            }
            if configuration.colourBands == nil {
            HStack(spacing: 12) {
                Toggle("Threshold colours", isOn: Binding(get: { hasThresholds }, set: { enabled in
                    edit {
                        $0.warningThreshold = enabled ? defaultWarning : nil
                        $0.criticalThreshold = enabled ? defaultCritical : nil
                        if $0.isCombinedNetwork {
                            $0.downloadWarningThreshold = enabled ? store.settings.networkCeiling * 0.7 : nil
                            $0.downloadCriticalThreshold = enabled ? store.settings.networkCeiling * 0.9 : nil
                        }
                    }
                })).font(.caption)
                if hasThresholds {
                    Picker("Direction", selection: column(\.thresholdDirection)) {
                        Text("Above").tag(ThresholdDirection.above)
                        Text("Below").tag(ThresholdDirection.below)
                    }.labelsHidden().frame(width: 85)
                }
            }
            if hasThresholds {
                HStack {
                    if configuration.isCombinedNetwork { Text("Upload").font(.caption).frame(width: 60, alignment: .leading) }
                    Text("Warning").font(.caption)
                    thresholdField(\.warningThreshold, fallback: defaultWarning)
                    Text("Critical").font(.caption)
                    thresholdField(\.criticalThreshold, fallback: defaultCritical)
                    Text(unit).font(.caption).foregroundColor(.secondary)
                }
                if configuration.isCombinedNetwork {
                    HStack {
                        Text("Download").font(.caption).frame(width: 60, alignment: .leading)
                        Text("Warning").font(.caption)
                        thresholdField(\.downloadWarningThreshold, fallback: store.settings.networkCeiling * 0.7)
                        Text("Critical").font(.caption)
                        thresholdField(\.downloadCriticalThreshold, fallback: store.settings.networkCeiling * 0.9)
                        Text(unit).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            }
        }.padding(12).background(Color.primary.opacity(0.04)).cornerRadius(8)
    }

    private var index: Int? { store.settings.columns.firstIndex(where: { $0.id == id }) }
    // SwiftUI can read an old binding after removal; its fallback is never written back.
    private var configuration: ColumnConfiguration {
        store.settings.columns.first(where: { $0.id == id }) ?? ColumnConfiguration(metric: .cpu, colour: .mint)
    }
    private var isNetwork: Bool { configuration.isCombinedNetwork || configuration.metric == .download || configuration.metric == .upload }
    private var unit: String { isNetwork ? "B/s" : configuration.metric == .thermal ? "level 0–3" : "%" }
    private var defaultWarning: Double { isNetwork ? store.settings.networkCeiling(for: configuration.metric) * 0.7 : configuration.metric == .thermal ? 2 : configuration.thresholdDirection == .below ? 30 : 70 }
    private var defaultCritical: Double { isNetwork ? store.settings.networkCeiling(for: configuration.metric) * 0.9 : configuration.metric == .thermal ? 3 : configuration.thresholdDirection == .below ? 10 : 90 }

    private var hasThresholds: Bool {
        configuration.warningThreshold != nil || configuration.criticalThreshold != nil
            || configuration.downloadWarningThreshold != nil || configuration.downloadCriticalThreshold != nil
    }

    private var colourBandsEditor: some View {
        let bands = configuration.colourBands
        let stops = bands?.stops ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Colours", selection: Binding(get: { stops.count + 1 }, set: { count in
                edit { column in
                    guard count > 1 else { column.colourBands = nil; return }
                    var next = column.colourBands ?? ColourBands()
                    let kept = Array(next.stops.prefix(count - 1))
                    next.stops = kept + ColourBands.defaults(count: count).dropFirst(kept.count)
                    column.colourBands = next
                }
            })) {
                ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented).frame(width: 220)
            HStack(alignment: .top, spacing: 12) {
                if let first = stops.first {
                    // Colour 1 covers everything below the first threshold.
                    HStack {
                        Text("Below").font(.caption).frame(width: 70, alignment: .leading)
                        Text(String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), first.threshold))
                            .foregroundColor(.secondary).padding(.leading, 4).frame(width: 50, alignment: .leading)
                        Text("%").font(.caption)
                    }
                }
                PaletteColourPicker(title: stops.isEmpty ? "Colour" : "Colour 1", selection: column(\.colour), showsTitle: false)
            }
            ForEach(stops.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    HStack {
                        Text("At or above").font(.caption).frame(width: 70, alignment: .leading)
                        DecimalField(placeholder: "%", value: Binding(get: { stops[index].threshold }, set: { value in
                            edit { $0.colourBands?.stops[index].threshold = value }
                        })).frame(width: 50)
                        Text("%").font(.caption)
                    }
                    PaletteColourPicker(title: "Colour \(index + 2)", selection: Binding(get: { stops[index].colour }, set: { colour in
                        edit { $0.colourBands?.stops[index].colour = colour }
                    }), showsTitle: false)
                }
            }
            if let bands {
                Toggle("Gradient", isOn: Binding(get: { bands.gradient }, set: { on in edit { $0.colourBands?.gradient = on } })).font(.caption)
                ColourBandsPreview(bands: bands, base: configuration.colour).frame(width: 220, height: 10)
            }
        }
    }

    private func column<Value>(_ keyPath: WritableKeyPath<ColumnConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func colourPicker(_ title: String, keyPath: WritableKeyPath<ColumnConfiguration, MeterColour>) -> some View {
        PaletteColourPicker(title: title, selection: column(keyPath))
    }

    private func thresholdField(_ keyPath: WritableKeyPath<ColumnConfiguration, Double?>, fallback: Double) -> some View {
        DecimalField(placeholder: "Value", value: Binding(get: { configuration[keyPath: keyPath] ?? fallback }, set: { value in edit { $0[keyPath: keyPath] = value } })).frame(width: 90)
    }

    private func edit(_ change: (inout ColumnConfiguration) -> Void) {
        store.change { settings in
            guard let index = settings.columns.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.columns[index])
        }
    }

    private func move(offset: Int) {
        store.change { settings in
            guard let index = settings.columns.firstIndex(where: { $0.id == id }) else { return }
            let destination = index + offset
            guard settings.columns.indices.contains(destination) else { return }
            let target = offset < 0 ? settings.columns[destination].id : settings.columns.dropFirst(destination + 1).first?.id
            _ = WidgetOrganization.moveColumn(in: &settings, id: id, before: target)
        }
    }
}

private struct PanelEditor: View {
    @ObservedObject var store: MonitoringStore
    let id: UUID

    private var panel: PanelConfiguration {
        store.settings.panels.first { $0.id == id } ?? PanelConfiguration(metric: .cpu, id: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: Binding(get: { panel.isCombinedNetwork ? "combined" : panel.metric.rawValue }, set: { value in
                edit { panel in
                    panel.isCombinedNetwork = value == "combined"
                    panel.metric = MetricID(rawValue: value) ?? .download
                }
            })) {
                Text("Upload / Download").tag("combined")
                ForEach(MetricID.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Card size", selection: configuration(\.appearance.size)) {
                ForEach(PanelCardSize.allCases) { Text($0.title).tag($0) }
            }
            if panel.appearance.size == .large {
                Picker("Large card layout", selection: configuration(\.appearance.largeOrientation)) {
                    ForEach(PanelLargeOrientation.allCases) { Text($0.title).tag($0) }
                }
            }
            if panel.isNetwork {
                Toggle("Show connection details", isOn: configuration(\.appearance.showsConnectionDetails))
                if panel.appearance.showsConnectionDetails {
                    ConnectionFieldsEditor(fields: configuration(\.appearance.connectionFields)).padding(.leading, 18)
                }
                NetworkInterfacePicker(selection: configuration(\.networkInterface), snapshot: store.snapshot)
                SelectedInterfaceDetails(selection: panel.networkInterface, snapshot: store.snapshot)
            }
            if StatusPanelLayout.supportsHistory(panel.metric) {
                PaletteColourPicker(title: "Graph colour", selection: configuration(\.appearance.colour))
                Toggle("Show history graph", isOn: configuration(\.appearance.showsHistory))
            }
        }
    }

    private func configuration<Value>(_ keyPath: WritableKeyPath<PanelConfiguration, Value>) -> Binding<Value> {
        Binding(get: { panel[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }
    private func edit(_ change: (inout PanelConfiguration) -> Void) {
        store.change { settings in
            guard let index = settings.panels.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.panels[index])
        }
    }
}

/// 0–100% strip showing the colour each level renders with.
private struct ColourBandsPreview: View {
    let bands: ColourBands
    let base: MeterColour

    var body: some View {
        // ponytail: sampled at 1% steps; exact enough for a 220pt preview.
        HStack(spacing: 0) {
            ForEach(0..<101, id: \.self) { level in
                let band = bands.colour(for: Double(level), base: base)
                let from = band.from.nsColor.usingColorSpace(.sRGB) ?? band.from.nsColor
                Rectangle().fill(Color(from.blended(withFraction: CGFloat(band.fraction), of: band.to.nsColor) ?? from))
            }
        }.cornerRadius(3)
            .accessibilityLabel("Colour preview from 0 to 100 percent")
    }
}

/// Automatic (fit the most useful rows to the card) or a manual checkbox set.
private struct ConnectionFieldsEditor: View {
    @Binding var fields: Set<NetworkDetailField>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Choose details manually", isOn: Binding(get: { fields != nil }, set: { manual in
                fields = manual ? [.ipv4, .router, .dns] : nil
            })).font(.caption)
            if let chosen = fields {
                HStack(alignment: .top, spacing: 24) {
                    column(Array(NetworkDetailField.priority.prefix(5)), chosen: chosen)
                    column(Array(NetworkDetailField.priority.dropFirst(5)), chosen: chosen)
                }
                Text("Chosen details that do not fit this card size are left out; larger cards show more.").font(.caption).foregroundColor(.secondary)
            } else {
                Text("Shows the most useful details that fit the card: IPv4, router, DNS, mask, MAC, then the rest.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func column(_ items: [NetworkDetailField], chosen: Set<NetworkDetailField>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { field in
                Toggle(field.title, isOn: Binding(get: { chosen.contains(field) }, set: { on in
                    var next = chosen
                    if on { next.insert(field) } else { next.remove(field) }
                    fields = next
                })).font(.caption)
            }
        }
    }
}
