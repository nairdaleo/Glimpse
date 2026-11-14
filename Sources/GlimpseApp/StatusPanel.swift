import SwiftUI
import GlimpseCore

struct StatusPanel: View {
    @ObservedObject var store: MonitoringStore
    var showSettings: () -> Void
    var editCard: (MetricID) -> Void
    var maximumSize: CGSize

    init(store: MonitoringStore, showSettings: @escaping () -> Void, editCard: @escaping (MetricID) -> Void,
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
                    if store.settings.panelMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("All detail panels are hidden.").font(.callout)
                            Button("Choose panels…", action: showSettings).font(.caption)
                        }.frame(width: layout.gridWidth, height: layout.gridHeight, alignment: .leading)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: StatusPanelLayout.spacing, alignment: .topLeading), count: layout.columns),
                                  alignment: .leading, spacing: StatusPanelLayout.spacing) {
                            ForEach(store.settings.panelMetrics) { metric in
                                MetricCard(metric: metric, reading: store.snapshot.readings[metric],
                                           points: store.history.samples[metric] ?? [], settings: store.settings,
                                           width: layout.cardWidth, height: layout.cardHeights[metric] ?? 150,
                                           edit: { editCard(metric) })
                            }
                        }.frame(width: layout.gridWidth, alignment: .leading)
                    }
                    if layout.showsNetwork {
                        Text(store.snapshot.networkInterface.isEmpty ? "Network: finding an interface…" : "Network: \(store.snapshot.networkInterface)")
                            .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                            .frame(width: layout.gridWidth, height: StatusPanelLayout.networkHeight, alignment: .leading)
                            .help("One interface at a time. History stays on this Mac and clears when you quit.")
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
    let metric: MetricID
    let reading: MetricReading?
    let points: [HistoryPoint]
    let settings: AppSettings
    let width: CGFloat
    let height: CGFloat
    var edit: () -> Void

    private var appearance: PanelAppearance { settings.panelAppearance(for: metric) }
    private var compact: Bool { appearance.size == .compact }
    private var large: Bool { appearance.size == .large }

    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                Text(metric.title).font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundColor(.secondary)
                Text(MetricPresentation.formatted(value: reading?.value, metric: metric, bits: settings.bandwidthInBits))
                    .font(.system(size: compact ? 18 : large ? 28 : 21, weight: .medium, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if appearance.showsHistory && StatusPanelLayout.supportsHistory(metric) {
                    HistoryGraph(points: points, ceiling: ceiling, colour: Color(appearance.colour.nsColor))
                        .frame(height: compact ? 14 : large ? 48 : 30)
                        .accessibilityLabel("Recent \(metric.title) history")
                }
                Text(reading?.detail ?? "Waiting for a reading")
                    .font(.system(size: compact ? 9 : 10)).foregroundColor(.secondary)
                    .lineLimit(compact ? 1 : large ? 4 : 3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            }.padding(11).frame(width: width, height: height, alignment: .topLeading)
                .background(Color.primary.opacity(0.045)).cornerRadius(9)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens settings for this card")
            .help("Edit \(metric.title) card settings")
    }

    private var ceiling: Double {
        metric == .download || metric == .upload ? settings.networkCeiling : 100
    }
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
