import SwiftUI
import UniformTypeIdentifiers
import GlimpseCore

struct StatusPanel: View {
    @ObservedObject var store: MonitoringStore
    var showSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 25, weight: .semibold)).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glimpse").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Your Mac, at a glance").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let age = max(0, Int(ProcessInfo.processInfo.systemUptime - store.snapshot.timestamp))
                    let stale = Double(age) > max(10, store.settings.refreshInterval * 3)
                    Label("\(stale ? "Paused" : "Live") · \(age)s", systemImage: stale ? "pause.circle.fill" : "circle.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(stale ? .orange : .secondary)
                }
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("IN YOUR MENU BAR").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading, spacing: 12) {
                        ForEach(store.settings.columns) { column in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 4) {
                                    Circle().fill(Color(column.colour.nsColor)).frame(width: 5, height: 5)
                                    Text(column.metric.title).font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Text(value(column.metric)).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(store.settings.panelMetrics) { metric in
                            MetricCard(metric: metric, reading: store.snapshot.readings[metric], points: store.history.samples[metric] ?? [], settings: store.settings,
                                       hide: { store.change { WidgetOrganization.setPanel(in: &$0, metric: metric, visible: false) } })
                                .onDrag { OrganizationDragPayload.panel(metric).provider }
                                .onDrop(of: [UTType.text], delegate: panelDrop(store: store, before: metric))
                                .contextMenu {
                                    Button("Move up") { movePanel(metric, offset: -1) }.disabled(store.settings.panelMetrics.first == metric)
                                    Button("Move down") { movePanel(metric, offset: 1) }.disabled(store.settings.panelMetrics.last == metric)
                                    Button("Hide panel") { store.change { WidgetOrganization.setPanel(in: &$0, metric: metric, visible: false) } }
                                }
                                .accessibilityAction(named: Text("Move up")) { movePanel(metric, offset: -1) }
                                .accessibilityAction(named: Text("Move down")) { movePanel(metric, offset: 1) }
                        }
                    }
                    if store.settings.panelMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("All detail panels are hidden.").font(.callout)
                            Menu("Restore a panel") {
                                ForEach(MetricID.allCases) { metric in
                                    Button(metric.title) { store.change { WidgetOrganization.setPanel(in: &$0, metric: metric, visible: true) } }
                                }
                            }
                            Button("Manage panels in settings", action: showSettings).font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Color.primary.opacity(0.045)).cornerRadius(9)
                    } else {
                        Text("Drag cards to reorder · more options with a secondary click")
                            .font(.system(size: 9)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 20)
                            .onDrop(of: [UTType.text], delegate: panelDrop(store: store, before: nil))
                    }
                    if showsNetwork {
                        VStack(alignment: .leading, spacing: 4) {
                        Text(store.snapshot.networkInterface.isEmpty ? "Network: finding an interface…" : "Network: \(store.snapshot.networkInterface)")
                            .font(.system(size: 11, weight: .medium))
                        Text("One interface at a time. History stays on this Mac and clears when you quit.")
                            .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(18)
            }
            Divider()
            HStack {
                Button(action: showSettings) { Image(systemName: "gearshape").frame(width: 22, height: 20) }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings… (⌘,)").accessibilityLabel("Settings")
                Spacer()
                Text("Recent history · up to 5 min").font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain).font(.system(size: 11)).padding(14)
        }
        .frame(width: 360, height: 590)
    }

    private func value(_ metric: MetricID) -> String {
        MetricPresentation.formatted(value: store.snapshot.readings[metric]?.value, metric: metric, bits: store.settings.bandwidthInBits)
    }

    private var showsNetwork: Bool {
        store.settings.showBandwidth || store.settings.columns.contains { $0.metric == .download || $0.metric == .upload }
            || store.settings.panelMetrics.contains { $0 == .download || $0 == .upload }
    }

    private func movePanel(_ metric: MetricID, offset: Int) {
        store.change { settings in
            guard let index = settings.panelMetrics.firstIndex(of: metric) else { return }
            let destination = index + offset
            guard settings.panelMetrics.indices.contains(destination) else { return }
            let target = offset < 0 ? settings.panelMetrics[destination] : settings.panelMetrics.dropFirst(destination + 1).first
            _ = WidgetOrganization.movePanel(in: &settings, metric: metric, before: target)
        }
    }
}

private struct MetricCard: View {
    let metric: MetricID
    let reading: MetricReading?
    let points: [HistoryPoint]
    let settings: AppSettings
    var hide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.title).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                Spacer(minLength: 2)
                Button(action: hide) { Image(systemName: "eye.slash").font(.system(size: 10)) }
                    .buttonStyle(.plain).help("Hide \(metric.title) panel")
                    .accessibilityLabel("Hide \(metric.title) panel")
            }
            Text(MetricPresentation.formatted(value: reading?.value, metric: metric, bits: settings.bandwidthInBits))
                .font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if [.cpu, .memory, .download, .upload].contains(metric) {
                HistoryGraph(points: points, ceiling: ceiling).frame(height: 26)
                    .accessibilityLabel("Recent \(metric.title) history")
            }
            Text(reading?.detail ?? "Waiting for a reading")
                .font(.system(size: 9)).foregroundColor(.secondary).lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .topLeading)
        }
        .padding(11).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045)).cornerRadius(9)
        .accessibilityElement(children: .contain)
        .help(reading.map { "Updated \(max(0, Int(ProcessInfo.processInfo.systemUptime - $0.timestamp))) seconds ago" } ?? "No reading collected yet")
    }

    private var ceiling: Double {
        if metric == .download || metric == .upload { return settings.networkCeiling }
        return 100
    }
}

private struct HistoryGraph: View {
    let points: [HistoryPoint]
    let ceiling: Double

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let end = points.last?.timestamp ?? 0
                let start = end - 300
                var connected = false
                var lastTime: TimeInterval?
                for point in points {
                    guard point.timestamp >= start, let value = point.value, value.isFinite else {
                        connected = false
                        continue
                    }
                    if let lastTime = lastTime, point.timestamp - lastTime > 65 { connected = false }
                    let x = CGFloat((point.timestamp - start) / 300) * geometry.size.width
                    let y = geometry.size.height * CGFloat(1 - min(1, max(0, value / max(1, ceiling))))
                    if connected { path.addLine(to: CGPoint(x: x, y: y)) }
                    else { path.move(to: CGPoint(x: x, y: y)); connected = true }
                    lastTime = point.timestamp
                }
            }.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
            }.stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
        }
    }
}
