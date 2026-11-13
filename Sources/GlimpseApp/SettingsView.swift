import SwiftUI
import GlimpseCore

struct SettingsView: View {
    @ObservedObject var store: MonitoringStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make room for what matters.").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Three meters. Your choice of information.").foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.fill").font(.system(size: 30)).foregroundColor(.accentColor)
            }.padding(.bottom, 6)
            TabView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(0..<3) { index in
                            ColumnEditor(store: store, index: index)
                        }
                        Text("Fill shows magnitude. Optional warning colours use the metric’s own units. Memory usage is not memory pressure.")
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(16)
                }.tabItem { Text("Columns") }
                displaySettings.padding(20).tabItem { Text("Display & Network") }
                generalSettings.padding(20).tabItem { Text("General") }
            }
            HStack {
                Text("Glimpse · MIT licensed").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Reset settings") { store.resetSettings() }
            }
        }.padding(22).frame(minWidth: 560, idealWidth: 590, minHeight: 570)
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
        VStack(alignment: .leading, spacing: 20) {
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
            Text("To start at login, add Glimpse in your Mac’s Login Items settings. To remove it, quit Glimpse, remove the login item, and move the app to the Trash.")
                .font(.caption).foregroundColor(.secondary)
            Link("Source code & issue tracker", destination: URL(string: "https://github.com/nairdaleo/Glimpse")!)
            Spacer()
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
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Column \(index + 1)").font(.headline)
                Spacer()
                if index > 0 {
                    Button("Move left") { store.change { $0.columns.swapAt(index, index - 1) } }.font(.caption)
                }
                if index < 2 {
                    Button("Move right") { store.change { $0.columns.swapAt(index, index + 1) } }.font(.caption)
                }
            }
            HStack {
                Picker("Metric", selection: column(\.metric)) {
                    ForEach(MetricID.allCases) { Text($0.title).tag($0) }
                }
                Picker("Colour", selection: column(\.colour)) {
                    ForEach(MeterColour.allCases) { colour in Text(colour.title).tag(colour) }
                }.frame(width: 155)
            }
            HStack(spacing: 12) {
                Toggle("Threshold colours", isOn: Binding(get: { configuration.warningThreshold != nil || configuration.criticalThreshold != nil }, set: { enabled in
                    store.change {
                        $0.columns[index].warningThreshold = enabled ? defaultWarning : nil
                        $0.columns[index].criticalThreshold = enabled ? defaultCritical : nil
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

    private var configuration: ColumnConfiguration { store.settings.columns[index] }
    private var isNetwork: Bool { configuration.metric == .download || configuration.metric == .upload }
    private var unit: String { isNetwork ? "B/s" : configuration.metric == .thermal ? "level 0–3" : "%" }
    private var defaultWarning: Double { isNetwork ? store.settings.networkCeiling * 0.7 : configuration.metric == .thermal ? 2 : configuration.thresholdDirection == .below ? 30 : 70 }
    private var defaultCritical: Double { isNetwork ? store.settings.networkCeiling * 0.9 : configuration.metric == .thermal ? 3 : configuration.thresholdDirection == .below ? 10 : 90 }

    private func column<Value>(_ keyPath: WritableKeyPath<ColumnConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in store.change { $0.columns[index][keyPath: keyPath] = value } })
    }

    private func thresholdField(_ keyPath: WritableKeyPath<ColumnConfiguration, Double?>, fallback: Double) -> some View {
        TextField("Value", value: Binding(get: { configuration[keyPath: keyPath] ?? fallback }, set: { value in store.change { $0.columns[index][keyPath: keyPath] = value } }), formatter: SettingsView.numberFormatter).frame(width: 90)
    }
}
