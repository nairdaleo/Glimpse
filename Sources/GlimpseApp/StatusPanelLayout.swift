import Foundation
import GlimpseCore

struct StatusPanelLayout {
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 14
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 44
    static let networkHeight: CGFloat = 24

    let size: CGSize
    let columns: Int
    let cardWidth: CGFloat
    let gridWidth: CGFloat
    let cardHeights: [MetricID: CGFloat]
    let panelHeights: [UUID: CGFloat]
    let rowHeights: [CGFloat]
    let gridHeight: CGFloat
    let showsNetwork: Bool

    init(settings: AppSettings, maximumSize: CGSize) {
        let settings = settings.validated()
        columns = min(settings.panelColumns, max(1, settings.panels.count))
        cardWidth = CGFloat(settings.panelCardWidth)
        gridWidth = settings.panels.isEmpty ? 182 : CGFloat(columns) * cardWidth + CGFloat(columns - 1) * Self.spacing
        cardHeights = settings.panels.reduce(into: [:]) { $0[$1.metric] = Self.height(for: $1.appearance.size) }
        panelHeights = Dictionary(uniqueKeysWithValues: settings.panels.map { ($0.id, Self.height(for: $0.appearance.size)) })
        var heights: [CGFloat] = []
        for start in stride(from: 0, to: settings.panels.count, by: columns) {
            let row = settings.panels[start..<min(start + columns, settings.panels.count)]
            heights.append(row.map { Self.height(for: $0.appearance.size) }.max() ?? 0)
        }
        rowHeights = heights
        gridHeight = heights.isEmpty ? 100 : heights.reduce(0, +) + CGFloat(heights.count - 1) * Self.spacing
        showsNetwork = settings.panels.contains { $0.isNetwork }
        let desired = CGSize(width: max(210, gridWidth + Self.padding * 2),
                             height: Self.headerHeight + Self.footerHeight + gridHeight + Self.padding * 2 + (showsNetwork ? Self.networkHeight : 0) + 2)
        let maximumWidth = maximumSize.width.isFinite && maximumSize.width > 0 ? maximumSize.width : desired.width
        let maximumHeight = maximumSize.height.isFinite && maximumSize.height > 0 ? maximumSize.height : desired.height
        size = CGSize(width: min(desired.width, maximumWidth), height: min(desired.height, maximumHeight))
    }

    static func height(for size: PanelCardSize) -> CGFloat {
        switch size {
        case .compact: return 100
        case .regular: return 150
        case .large: return 190
        }
    }

    static func supportsHistory(_ metric: MetricID) -> Bool {
        [.cpu, .memory, .download, .upload].contains(metric)
    }
}
