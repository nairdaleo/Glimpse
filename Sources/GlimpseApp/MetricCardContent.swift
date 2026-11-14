import SwiftUI
import GlimpseCore

/// The actual card surface, shared by the dropdown and its settings preview.
/// Selection and editing actions belong to the containing view.
struct MetricCardContent: View {
    let panel: PanelConfiguration
    let snapshot: Snapshot
    let history: MetricHistory
    let networkHistory: NetworkHistory
    let settings: AppSettings
    let width: CGFloat
    let height: CGFloat

    private var appearance: PanelAppearance { panel.appearance }
    private var compact: Bool { appearance.size == .compact }
    private var wide: Bool { appearance.size == .large && appearance.largeOrientation == .horizontal }
    private var large: Bool { appearance.size == .large }
    private var reading: MetricReading? { snapshot.displayReading(for: panel.metric, interface: panel.networkInterface) }
    private var showsHistory: Bool { appearance.showsHistory && StatusPanelLayout.supportsHistory(panel.metric) }
    private var showsDetails: Bool { panel.isNetwork && appearance.showsConnectionDetails }

    var body: some View {
        Group {
            if compact { compactContent }
            else if wide { horizontalContent }
            else { verticalContent }
        }
        .padding(compact ? 8 : 11)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.primary.opacity(0.045)).cornerRadius(9)
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 4) {
                title(size: 9).lineLimit(2)
                Spacer(minLength: 0)
                values(size: panel.isCombinedNetwork ? 10 : 17).layoutPriority(1)
            }
            if panel.isNetwork { interfaceIdentifier }
            if showsDetails {
                connectionDetails(availableWidth: width - 16)
            } else if showsHistory {
                graph.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 8)
            } else if !panel.isNetwork {
                readingDetail(lines: 1, size: 9)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            title(size: 11)
            if panel.isNetwork { interfaceIdentifier }
            values(size: panel.isCombinedNetwork ? (large ? 23 : 15) : (large ? 28 : 21))
            if showsHistory { graph.frame(height: large ? 70 : (showsDetails ? 20 : 28)) }
            if showsDetails {
                connectionDetails(availableWidth: width - 22)
            } else if !panel.isCombinedNetwork || large {
                readingDetail(lines: large ? 5 : 2, size: 10)
            }
            if !showsDetails { Spacer(minLength: 0) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var horizontalContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                title(size: 11)
                if panel.isNetwork { interfaceIdentifier }
                values(size: panel.isCombinedNetwork ? 19 : 28)
            }.frame(width: max(92, (width - 34) * 0.38), alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if showsHistory { graph.frame(height: showsDetails ? 38 : 62) }
                if showsDetails {
                    connectionDetails(availableWidth: max(100, (width - 34) * 0.62))
                } else {
                    readingDetail(lines: 4, size: 10)
                    Spacer(minLength: 0)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func title(size: CGFloat) -> some View {
        Text(panel.displayTitle).font(.system(size: size, weight: .medium)).foregroundColor(.secondary)
    }

    private func values(size: CGFloat) -> some View {
        Group {
            if panel.isCombinedNetwork {
                VStack(alignment: .leading, spacing: 1) {
                    Text("↑ " + formatted(.upload)).accessibilityLabel("Upload " + formatted(.upload))
                    Text("↓ " + formatted(.download)).accessibilityLabel("Download " + formatted(.download))
                }
            } else { Text(formatted(panel.metric)) }
        }
        .font(.system(size: size, weight: .medium, design: .rounded))
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
    }

    private var interfaceIdentifier: some View {
        let name = panel.networkInterface ?? snapshot.automaticNetworkInterface
        return Text((panel.networkInterface == nil ? "Auto · " : "") + (name ?? "unavailable"))
            .font(.system(size: compact ? 9 : 10)).foregroundColor(.secondary).lineLimit(1)
            .help(snapshot.interfaceLabel(panel.networkInterface))
    }

    private func readingDetail(lines: Int, size: CGFloat) -> some View {
        Text(reading?.detail ?? "Waiting for a reading")
            .font(.system(size: size)).foregroundColor(.secondary).lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func connectionDetails(availableWidth: CGFloat) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Group {
                if let info = snapshot.networkInfo(for: panel.networkInterface) {
                    NetworkInterfaceDetails(info: info)
                } else {
                    Text("Connection details are unavailable.").font(.caption).foregroundColor(.secondary)
                }
            }.frame(width: max(280, availableWidth), alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Connection details for " + snapshot.interfaceLabel(panel.networkInterface))
    }

    private var graph: some View {
        ZStack {
            CardHistoryGraph(points: points(panel.metric), ceiling: ceiling, colour: Color(appearance.colour.nsColor))
            if panel.isCombinedNetwork {
                CardHistoryGraph(points: points(.upload), ceiling: ceiling, colour: Color(appearance.colour.nsColor).opacity(0.5))
            }
        }.accessibilityLabel("Recent \(panel.displayTitle) history")
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

private struct CardHistoryGraph: View {
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
                    if let lastTime, point.timestamp - lastTime > 65 { connected = false }
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
