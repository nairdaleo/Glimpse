import SwiftUI
import UniformTypeIdentifiers
import GlimpseCore

struct SettingsView: View {
    private enum Tab: Hashable { case columns, panels, display, general }
    @ObservedObject var store: MonitoringStore
    @ObservedObject var services: LifecycleServices
    @State private var selectedColumnID: UUID? = nil
    @State private var selectedPanelID: MetricID? = nil
    @State private var selectedTab: Tab = .columns

    init(store: MonitoringStore, services: LifecycleServices, requestedPanel: MetricID? = nil) {
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
                panelSettings.tabItem { Text("Dropdown Panels") }.tag(Tab.panels)
                displaySettings.padding(20).tabItem { Text("Display & Network") }.tag(Tab.display)
                generalSettings.padding(20).tabItem { Text("General") }.tag(Tab.general)
            }
            HStack {
                Text("Glimpse · MIT licensed").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Reset settings") { store.resetSettings() }
            }
        }.padding(22).frame(minWidth: 560, idealWidth: 590, minHeight: 570)
            .onAppear { services.refreshLoginStatus() }
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
                Text("Drag a meter before another to reorder it. Select a meter to edit its colour and thresholds.")
                    .font(.caption).foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 8) {
                        ForEach(Array(store.settings.columns.enumerated()), id: \.element.id) { index, column in
                            Button { selectedColumnID = column.id } label: {
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
                                }
                                .frame(width: 94, height: 84)
                                .background(selectedID == column.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedID == column.id ? Color.accentColor : Color.clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Meter \(index + 1), \(column.displayTitle)")
                            .accessibilityAddTraits(selectedID == column.id ? .isSelected : [])
                            .onDrag { OrganizationDragPayload.column(column.id).provider }
                            .onDrop(of: [UTType.text], delegate: columnDrop(store: store, before: column.id))
                        }
                        Text("Drop at end").font(.caption).foregroundColor(.secondary)
                            .frame(width: 70, height: 84).background(Color.primary.opacity(0.025)).cornerRadius(8)
                            .onDrop(of: [UTType.text], delegate: columnDrop(store: store, before: nil))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Cards per row", selection: setting(\.panelColumns)) {
                    ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                }.frame(width: 210)
                HStack {
                    Text("Card width")
                    Slider(value: setting(\.panelCardWidth), in: 120...240, step: 4).accessibilityLabel("Card width")
                    Text("\(Int(store.settings.panelCardWidth)) pt").monospacedDigit().frame(width: 50, alignment: .trailing)
                }
                Text("Visible panels").font(.headline)
                Text("Drag cards into order. Select a card to edit its size and graph. The dropdown uses this arrangement.")
                    .font(.caption).foregroundColor(.secondary)
                if store.settings.panelMetrics.isEmpty {
                    Text("All dropdown panels are hidden. Restore one below.")
                        .font(.callout).foregroundColor(.secondary).padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 8) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(112), spacing: 8), count: organizerColumns), spacing: 8) {
                                ForEach(Array(store.settings.panelMetrics.enumerated()), id: \.element) { index, metric in
                                    Button { selectedPanelID = metric } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: "line.3.horizontal").font(.caption).foregroundColor(.secondary)
                                            Text("\(index + 1) · \(metric.title)").font(.caption)
                                            Text(store.settings.panelAppearance(for: metric).size.title).font(.caption2).foregroundColor(.secondary)
                                        }.frame(width: 112, height: 76)
                                            .background(selectedPanel == metric ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedPanel == metric ? Color.accentColor : Color.clear, lineWidth: 1.5))
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel("Panel \(index + 1), \(metric.title)")
                                        .accessibilityAddTraits(selectedPanel == metric ? .isSelected : [])
                                        .onDrag { OrganizationDragPayload.panel(metric).provider }
                                        .onDrop(of: [UTType.text], delegate: panelDrop(store: store, before: metric))
                                }
                            }
                            Text("Drop at end").font(.caption).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding(10).background(Color.primary.opacity(0.025)).cornerRadius(8)
                                .onDrop(of: [UTType.text], delegate: panelDrop(store: store, before: nil))
                        }.frame(width: CGFloat(organizerColumns) * 112 + CGFloat(organizerColumns - 1) * 8).padding(2)
                    }
                }
                if let metric = selectedPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(metric.title) panel").font(.headline)
                            Spacer()
                            Button("Move earlier") { movePanel(metric, offset: -1) }
                                .disabled(!store.settings.panelMetrics.contains(metric) || store.settings.panelMetrics.first == metric)
                            Button("Move later") { movePanel(metric, offset: 1) }
                                .disabled(!store.settings.panelMetrics.contains(metric) || store.settings.panelMetrics.last == metric)
                            Button("Hide") { store.change { WidgetOrganization.setPanel(in: &$0, metric: metric, visible: false) } }
                                .disabled(!store.settings.panelMetrics.contains(metric))
                        }.font(.caption)
                        PanelEditor(store: store, metric: metric)
                    }.padding(12).background(Color.primary.opacity(0.04)).cornerRadius(8)
                }
                if !hiddenPanels.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Hidden panels").font(.headline)
                    ForEach(hiddenPanels) { metric in
                        HStack {
                            Button(metric.title) { selectedPanelID = metric }.buttonStyle(.plain)
                                .accessibilityLabel("Edit hidden \(metric.title) panel")
                            Spacer()
                            Button("Restore") {
                                store.change { WidgetOrganization.setPanel(in: &$0, metric: metric, visible: true) }
                                selectedPanelID = metric
                            }.accessibilityLabel("Restore \(metric.title) panel")
                        }.padding(.vertical, 4)
                    }
                }
            }.padding(16)
        }
    }

    private var selectedPanel: MetricID? { selectedPanelID ?? store.settings.panelMetrics.first }
    private var organizerColumns: Int { min(store.settings.panelColumns, max(1, store.settings.panelMetrics.count)) }

    private var hiddenPanels: [MetricID] { MetricID.allCases.filter { !store.settings.panelMetrics.contains($0) } }

    private func movePanel(_ metric: MetricID, offset: Int) {
        store.change { settings in
            guard let index = settings.panelMetrics.firstIndex(of: metric) else { return }
            let destination = index + offset
            guard settings.panelMetrics.indices.contains(destination) else { return }
            let target = offset < 0 ? settings.panelMetrics[destination] : settings.panelMetrics.dropFirst(destination + 1).first
            _ = WidgetOrganization.movePanel(in: &settings, metric: metric, before: target)
        }
    }

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle("Show upload and download speeds beside the icon", isOn: setting(\.showBandwidth))
            Toggle("Use bits per second for bandwidth", isOn: setting(\.bandwidthInBits))
            Toggle("Use monochrome meter columns", isOn: setting(\.monochrome))
            Divider()
            HStack {
                Text("Network column full at")
                TextField("MB/s", value: Binding(get: { store.settings.networkCeiling / 1_000_000 }, set: { value in store.change { $0.networkCeiling = value * 1_000_000 } }), formatter: Self.numberFormatter)
                    .frame(width: 80)
                Text("MB/s (bytes)").foregroundColor(.secondary)
            }
            Picker("Measure traffic on", selection: Binding(get: { store.settings.networkInterface ?? "" }, set: { value in store.change { $0.networkInterface = value.isEmpty ? nil : value } })) {
                Text("Automatic · physical interface").tag("")
                ForEach(interfaceNames, id: \.self) { interface in Text(interface).tag(interface) }
            }
            Text("Automatic measures one active physical interface. Select a VPN interface explicitly to measure its tunnel traffic instead. Interfaces are never added together.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
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
            Link("Source code & issue tracker", destination: URL(string: "https://github.com/nairdaleo/Glimpse")!)
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
                        column.thresholdDirection = .above
                    }
                })) {
                    Text("Upload / Download").tag("combinedNetwork")
                    ForEach(MetricID.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if !configuration.isCombinedNetwork {
                    colourPicker("Colour", keyPath: \.colour).frame(width: 155)
                }
            }
            if configuration.isCombinedNetwork {
                HStack {
                    colourPicker("Upload", keyPath: \.colour)
                    colourPicker("Download", keyPath: \.secondaryColour)
                }
                Text("Upload fills above the center; download fills below.")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Toggle("Threshold colours", isOn: Binding(get: { configuration.warningThreshold != nil || configuration.criticalThreshold != nil }, set: { enabled in
                    edit {
                        $0.warningThreshold = enabled ? defaultWarning : nil
                        $0.criticalThreshold = enabled ? defaultCritical : nil
                    }
                })).font(.caption)
                if configuration.warningThreshold != nil || configuration.criticalThreshold != nil {
                    Picker("Direction", selection: column(\.thresholdDirection)) {
                        Text("Above").tag(ThresholdDirection.above)
                        Text("Below").tag(ThresholdDirection.below)
                    }.labelsHidden().frame(width: 85)
                }
            }
            if configuration.warningThreshold != nil || configuration.criticalThreshold != nil {
                HStack {
                    Text("Warning").font(.caption)
                    thresholdField(\.warningThreshold, fallback: defaultWarning)
                    Text("Critical").font(.caption)
                    thresholdField(\.criticalThreshold, fallback: defaultCritical)
                    Text(unit).font(.caption).foregroundColor(.secondary)
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
    private var defaultWarning: Double { isNetwork ? store.settings.networkCeiling * 0.7 : configuration.metric == .thermal ? 2 : configuration.thresholdDirection == .below ? 30 : 70 }
    private var defaultCritical: Double { isNetwork ? store.settings.networkCeiling * 0.9 : configuration.metric == .thermal ? 3 : configuration.thresholdDirection == .below ? 10 : 90 }

    private func column<Value>(_ keyPath: WritableKeyPath<ColumnConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func colourPicker(_ title: String, keyPath: WritableKeyPath<ColumnConfiguration, MeterColour>) -> some View {
        Picker(title, selection: column(keyPath)) {
            ForEach(MeterColour.allCases) { colour in Text(colour.title).tag(colour) }
        }
    }

    private func thresholdField(_ keyPath: WritableKeyPath<ColumnConfiguration, Double?>, fallback: Double) -> some View {
        TextField("Value", value: Binding(get: { configuration[keyPath: keyPath] ?? fallback }, set: { value in edit { $0[keyPath: keyPath] = value } }), formatter: SettingsView.numberFormatter).frame(width: 90)
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
    let metric: MetricID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Card size", selection: appearance(\.size)) {
                ForEach(PanelCardSize.allCases) { Text($0.title).tag($0) }
            }
            if StatusPanelLayout.supportsHistory(metric) {
                Picker("Graph colour", selection: appearance(\.colour)) {
                    ForEach(MeterColour.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show history graph", isOn: appearance(\.showsHistory))
            }
        }
    }

    private func appearance<Value>(_ keyPath: WritableKeyPath<PanelAppearance, Value>) -> Binding<Value> {
        Binding(get: { store.settings.panelAppearance(for: metric)[keyPath: keyPath] }, set: { value in
            store.change { settings in
                var appearance = settings.panelAppearance(for: metric)
                appearance[keyPath: keyPath] = value
                settings.panelAppearances[metric.rawValue] = appearance
            }
        })
    }
}
