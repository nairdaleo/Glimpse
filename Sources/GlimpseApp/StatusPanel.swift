import SwiftUI
import GlimpseCore

struct StatusPanel: View {
    @ObservedObject var store: MonitoringStore
    var showSettings: () -> Void
    var editCard: (UUID) -> Void
    var maximumSize: CGSize

    init(store: MonitoringStore, showSettings: @escaping () -> Void, editCard: @escaping (UUID) -> Void,
         maximumSize: CGSize = CGSize(width: 1600, height: 1000)) {
        self.store = store
        self.showSettings = showSettings
        self.editCard = editCard
        self.maximumSize = maximumSize
    }

    var body: some View {
        let layout = StatusPanelLayout(settings: store.settings, maximumSize: maximumSize)
        VStack(spacing: 0) {
            header.frame(height: StatusPanelLayout.headerHeight)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if store.settings.panels.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No detail panels added.").font(.callout)
                            Button("Choose panels…", action: showSettings).font(.caption)
                        }.frame(width: layout.gridWidth, height: layout.gridHeight, alignment: .leading)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: StatusPanelLayout.spacing, alignment: .topLeading), count: layout.columns),
                                  alignment: .leading, spacing: StatusPanelLayout.spacing) {
                            ForEach(store.settings.panels) { panel in
                                MetricCard(panel: panel, snapshot: store.snapshot, history: store.history,
                                           networkHistory: store.networkHistory, settings: store.settings,
                                           width: layout.cardWidth, height: layout.panelHeights[panel.id] ?? 150,
                                           edit: { editCard(panel.id) })
                            }
                        }.frame(width: layout.gridWidth, alignment: .leading)
                    }
                    if layout.showsNetwork {
                        Text("Auto: " + store.snapshot.interfaceLabel(nil))
                            .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                            .frame(width: layout.gridWidth, height: StatusPanelLayout.networkHeight, alignment: .leading)
                            .help("Each network panel measures its selected interface. History stays on this Mac and clears when you quit.")
                    }
                }.padding(StatusPanelLayout.padding)
            }
            Divider()
            HStack {
                Button(action: showSettings) { Image(systemName: "gearshape").frame(width: 22, height: 20) }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings… (⌘,)").accessibilityLabel("Settings")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 14)
                .frame(height: StatusPanelLayout.footerHeight)
        }.frame(width: layout.size.width, height: layout.size.height)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 12)).foregroundColor(.accentColor)
            Text("Glimpse").font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let age = max(0, Int(ProcessInfo.processInfo.systemUptime - store.snapshot.timestamp))
                let stale = Double(age) > max(10, store.settings.refreshInterval * 3)
                Label("\(stale ? "Paused" : "Live") · \(age)s", systemImage: stale ? "pause.circle.fill" : "circle.fill")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(stale ? .orange : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }.padding(.horizontal, 14)
    }
}

private struct MetricCard: View {
    let panel: PanelConfiguration
    let snapshot: Snapshot
    let history: MetricHistory
    let networkHistory: NetworkHistory
    let settings: AppSettings
    let width: CGFloat
    let height: CGFloat
    var edit: () -> Void

    private var appearance: PanelAppearance { panel.appearance }
    private var compact: Bool { appearance.size == .compact }
    private var large: Bool { appearance.size == .large }
    private var reading: MetricReading? { snapshot.displayReading(for: panel.metric, interface: panel.networkInterface) }
    private var graphHeight: CGFloat { compact ? 12 : large ? 44 : 28 }

    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text(panel.displayTitle).font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundColor(.secondary)
                if panel.isNetwork {
                    Text(snapshot.interfaceLabel(panel.networkInterface))
                        .font(.system(size: compact ? 9 : 10)).foregroundColor(.secondary).lineLimit(1)
                }
                if panel.isCombinedNetwork {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("↑ " + formatted(.upload))
                        Text("↓ " + formatted(.download))
                    }.font(.system(size: compact ? 11 : large ? 19 : 15, weight: .medium, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(formatted(panel.metric))
                        .font(.system(size: compact ? 18 : large ? 28 : 21, weight: .medium, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                if appearance.showsHistory && StatusPanelLayout.supportsHistory(panel.metric) {
                    ZStack {
                        HistoryGraph(points: points(panel.metric), ceiling: ceiling, colour: Color(appearance.colour.nsColor))
                        if panel.isCombinedNetwork {
                            HistoryGraph(points: points(.upload), ceiling: ceiling, colour: Color(appearance.colour.nsColor).opacity(0.5))
                        }
                    }.frame(height: graphHeight)
                        .accessibilityLabel("Recent \(panel.displayTitle) history")
                }
                if !compact || !panel.isNetwork {
                    if !panel.isCombinedNetwork || large {
                        Text(reading?.detail ?? "Waiting for a reading")
                            .font(.system(size: compact ? 9 : 10)).foregroundColor(.secondary)
                            .lineLimit(compact ? 1 : large ? 3 : 2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                Spacer(minLength: 0)
            }.padding(11).frame(width: width, height: height, alignment: .topLeading)
                .background(Color.primary.opacity(0.045)).cornerRadius(9)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens settings for this panel")
            .help("Edit \(panel.displayTitle) panel settings")
    }

    private func formatted(_ metric: MetricID) -> String {
        MetricPresentation.formatted(value: snapshot.displayReading(for: metric, interface: panel.networkInterface)?.value,
                                     metric: metric, bits: settings.bandwidthInBits)
    }
    private func points(_ metric: MetricID) -> [HistoryPoint] {
        panel.isNetwork ? networkHistory.points(for: metric, interface: panel.networkInterface, snapshot: snapshot) : history.samples[metric] ?? []
    }
    private var ceiling: Double { panel.isNetwork ? settings.networkCeiling : 100 }
}

private struct HistoryGraph: View {
    let points: [HistoryPoint]
    let ceiling: Double
    let colour: Color

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
            }.stroke(colour, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
            }.stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
        }
    }
}
