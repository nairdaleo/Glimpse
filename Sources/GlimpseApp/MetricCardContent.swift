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
        .background(Color.primary.opacity(0.045))
        .cornerRadius(9)
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
                connectionDetails()
            } else if showsHistory {
                graph.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 8)
            } else if panel.metric == .disk {
                capacityBar.frame(height: 5).padding(.top, 4)
                readingDetail(lines: 1, size: 9)
            } else if !panel.isNetwork {
                readingDetail(lines: panel.metric == .battery ? 2 : 1, size: 9)
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
                connectionDetails()
            } else if panel.metric == .cpu {
                perCoreActivity.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else if panel.metric == .disk {
                capacityBar.frame(height: 6).padding(.top, 2)
                readingDetail(lines: large ? 5 : 2, size: 10)
                Spacer(minLength: 0)
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
                    connectionDetails()
                } else if panel.metric == .cpu {
                    perCoreActivity.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                } else if panel.metric == .disk {
                    capacityBar.frame(height: 6).padding(.top, 2)
                    readingDetail(lines: 4, size: 10)
                    Spacer(minLength: 0)
                } else {
                    readingDetail(lines: 4, size: 10)
                    Spacer(minLength: 0)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var capacityBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule().fill(Color(appearance.colour.nsColor))
                    .frame(width: max(2, geometry.size.width * CGFloat((reading?.value ?? 0) / 100)))
            }.accessibilityLabel("Volume capacity")
        }
    }

    private var perCoreActivity: some View {
        let cores = panel.metric == .cpu ? snapshot.cpuCores : []
        let colour = Color(appearance.colour.nsColor)
        return HStack(alignment: .bottom, spacing: 2) {
            if cores.isEmpty {
                Text("Collecting per-core baseline")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            } else {
                ForEach(cores.indices, id: \.self) { index in
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(colour.opacity(0.22))
                            Capsule().fill(colour)
                                .frame(height: max(2, geometry.size.height * CGFloat(min(1, max(0, cores[index] / 100)))))
                        }
                    }
                }
            }
        }
        .accessibilityLabel(cores.isEmpty ? "Per-core activity is collecting a baseline" :
            "Per-core activity: " + cores.map { "\(Int($0))%" }.joined(separator: ", "))
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

    private func connectionDetails() -> some View {
        ScrollView([.vertical]) {
            Group {
                if let info = snapshot.networkInfo(for: panel.networkInterface) {
                    NetworkInterfaceDetails(info: info)
                } else {
                    Text("Connection details are unavailable.").font(.caption).foregroundColor(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Connection details for " + snapshot.interfaceLabel(panel.networkInterface))
    }

    private var graph: some View {
        let colour = Color(appearance.colour.nsColor)
        return Group {
            if panel.isCombinedNetwork {
                // Same reading order as the menu-bar duplex meter: upload on
                // the upper half, download on the lower half.
                VStack(spacing: 1) {
                    CardHistoryGraph(points: points(.upload), ceiling: ceiling(.upload), colour: colour,
                                     warning: networkThreshold(.upload)?.warning, critical: networkThreshold(.upload)?.critical)
                    CardHistoryGraph(points: points(.download), ceiling: ceiling(.download), colour: colour.opacity(0.5),
                                     warning: networkThreshold(.download)?.warning, critical: networkThreshold(.download)?.critical)
                }
            } else {
                CardHistoryGraph(points: points(panel.metric), ceiling: ceiling(panel.metric), colour: colour,
                                 warning: networkThreshold(panel.metric)?.warning, critical: networkThreshold(panel.metric)?.critical)
            }
        }.accessibilityLabel("Recent \(panel.displayTitle) history")
    }

    /// Warning/critical thresholds from the Network-tab column governing this
    /// metric: an exact metric + interface match first, then the combined
    /// column, then any column for the metric. Network panels only.
    private func networkThreshold(_ metric: MetricID) -> (warning: Double?, critical: Double?)? {
        guard panel.isNetwork else { return nil }
        let column = settings.columns.first { $0.metric == metric && $0.networkInterface == panel.networkInterface }
            ?? settings.columns.first { $0.isCombinedNetwork }
            ?? settings.columns.first { $0.metric == metric }
        guard let column else { return nil }
        return (column.warningThreshold, column.criticalThreshold)
    }

    private func formatted(_ metric: MetricID) -> String {
        MetricPresentation.formatted(value: snapshot.displayReading(for: metric, interface: panel.networkInterface)?.value,
                                     metric: metric, bits: settings.bandwidthInBits, units: settings.bandwidthUnits)
    }

    private func points(_ metric: MetricID) -> [HistoryPoint] {
        panel.isNetwork ? networkHistory.points(for: metric, interface: panel.networkInterface, snapshot: snapshot) : history.samples[metric] ?? []
    }

    private func ceiling(_ metric: MetricID) -> Double { panel.isNetwork ? settings.networkCeiling(for: metric) : 100 }
}

private struct CardHistoryGraph: View {
    let points: [HistoryPoint]
    let ceiling: Double
    let colour: Color
    var warning: Double? = nil
    var critical: Double? = nil

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
            ForEach(thresholdLines(height: geometry.size.height)) { line in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: line.y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: line.y))
                }.stroke(line.colour, style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
            }.stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
        }
    }

    /// Dashed horizontal lines at the warning (yellow) and critical (red)
    /// thresholds, scaled against the same ceiling as the readings. Missing
    /// thresholds draw nothing; the meter's level colours are reused.
    private func thresholdLines(height: CGFloat) -> [ThresholdLine] {
        var lines: [ThresholdLine] = []
        for (threshold, colour) in [(warning, Color(NSColor.systemYellow)), (critical, Color(NSColor.systemRed))] {
            guard let threshold, threshold.isFinite, threshold > 0, ceiling.isFinite, ceiling > 0 else { continue }
            let y = height * CGFloat(1 - min(1, max(0, threshold / ceiling)))
            lines.append(ThresholdLine(y: y, colour: colour))
        }
        return lines
    }
}

private struct ThresholdLine: Identifiable {
    let y: CGFloat
    let colour: Color
    var id: CGFloat { y }
}
