import Foundation
import GlimpseCore

struct StatusPanelLayout {
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 14
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 44
    static let networkHeight: CGFloat = 24
    static let halfRowHeight: CGFloat = 70

    let size: CGSize
    let columns: Int
    let cardWidth: CGFloat
    let gridWidth: CGFloat
    let cardHeights: [MetricID: CGFloat]
    let panelHeights: [UUID: CGFloat]
    let rowHeights: [CGFloat]
    let gridHeight: CGFloat
    let showsNetwork: Bool
    /// Top-left-origin card frames, shared by the Settings preview and live view.
    let placements: [UUID: CGRect]
    /// Compact pairs combined into one card: leading panel id → partner id.
    /// The partner has its own placement in the bottom half of the same slot.
    let embeds: [UUID: UUID]

    /// Shared card surfaces behind combined pairs, keyed by the leading panel id.
    var mergedSurfaces: [UUID: CGRect] {
        embeds.reduce(into: [:]) { result, pair in
            guard let top = placements[pair.key], let bottom = placements[pair.value] else { return }
            result[pair.key] = CGRect(x: top.minX, y: top.minY, width: top.width, height: bottom.maxY - top.minY)
        }
    }

    init(settings: AppSettings, maximumSize: CGSize) {
        let settings = settings.validated()
        cardWidth = CGFloat(settings.panelCardWidth)
        // A horizontal large card keeps its chosen orientation even when the
        // configured grid has one slot. Unused rightmost slots are trimmed later.
        let slotCount = max(settings.panelColumns, settings.panels.contains {
            $0.appearance.size == .large && $0.appearance.largeOrientation == .horizontal
        } ? 2 : 1)
        var occupied: Set<Int> = []
        var cursor = 0
        var usedColumns = 0
        var usedRows = 0
        var frames: [UUID: CGRect] = [:]
        var embeds: [UUID: UUID] = [:]
        for (index, panel) in settings.panels.enumerated() {
            if embeds.values.contains(panel.id) { continue }
            let span = Self.span(for: panel.appearance)
            // A compact card flagged combinesNext shares its regular slot with
            // the next compact card: two 75pt halves inside one 150pt slot.
            let partner = settings.panels.indices.contains(index + 1) ? settings.panels[index + 1] : nil
            let combines = panel.appearance.size == .compact && panel.appearance.combinesNext
                && partner?.appearance.size == .compact
            var start = cursor
            while true {
                // Visit the top and bottom compact halves of one regular
                // slot before moving right to the next slot.
                let half = start % 2
                let row = (start / (slotCount * 2)) * 2 + half
                let column = (start / 2) % slotCount
                if span.rows > 1 && half != 0 {
                    start += 1
                    continue
                }
                if column + span.columns > slotCount {
                    start += (slotCount - column) * 2
                    continue
                }
                let cells = (0..<span.rows).flatMap { dy in
                    (0..<span.columns).map { dx in (row + dy) * slotCount + column + dx }
                }
                if cells.allSatisfy({ !occupied.contains($0) }) {
                    occupied.formUnion(cells)
                    var height = CGFloat(span.rows) * Self.halfRowHeight + CGFloat(span.rows - 1) * Self.spacing
                    if combines && half == 0 && !occupied.contains(start + 1) {
                        // The pair fills the slot without the row gap: each
                        // half renders 75pt inside one shared card surface.
                        height = Self.halfRowHeight + Self.spacing / 2
                        if let partner {
                            embeds[panel.id] = partner.id
                            frames[partner.id] = CGRect(x: CGFloat(column) * (cardWidth + Self.spacing),
                                                        y: CGFloat(row) * (Self.halfRowHeight + Self.spacing) + height,
                                                        width: cardWidth, height: height)
                            occupied.insert(start + 1)
                            usedColumns = max(usedColumns, column + 1)
                            usedRows = max(usedRows, row + 2)
                        }
                    }
                    frames[panel.id] = CGRect(x: CGFloat(column) * (cardWidth + Self.spacing),
                                              y: CGFloat(row) * (Self.halfRowHeight + Self.spacing),
                                              width: CGFloat(span.columns) * cardWidth + CGFloat(span.columns - 1) * Self.spacing,
                                              height: height)
                    usedColumns = max(usedColumns, column + span.columns)
                    usedRows = max(usedRows, row + span.rows)
                    // Do not backfill earlier regular slots after advancing:
                    // compact pairs retain the organizer's reading order.
                    cursor = start + (combines && half == 0 ? 2 : 1)
                    break
                }
                start += 1
            }
        }
        placements = frames
        self.embeds = embeds
        columns = max(1, usedColumns)
        gridWidth = settings.panels.isEmpty ? 182 : CGFloat(columns) * cardWidth + CGFloat(columns - 1) * Self.spacing
        panelHeights = frames.mapValues(\.height)
        cardHeights = settings.panels.reduce(into: [:]) { $0[$1.metric] = frames[$1.id]?.height }
        rowHeights = Array(repeating: Self.halfRowHeight, count: usedRows)
        gridHeight = usedRows == 0 ? 100 : CGFloat(usedRows) * Self.halfRowHeight + CGFloat(usedRows - 1) * Self.spacing
        showsNetwork = settings.panels.contains { $0.isNetwork }
        let desired = CGSize(width: max(210, gridWidth + Self.padding * 2),
                             height: Self.headerHeight + Self.footerHeight + gridHeight + Self.padding * 2 + (showsNetwork ? Self.networkHeight : 0) + 2)
        let maximumWidth = maximumSize.width.isFinite && maximumSize.width > 0 ? maximumSize.width : desired.width
        let maximumHeight = maximumSize.height.isFinite && maximumSize.height > 0 ? maximumSize.height : desired.height
        size = CGSize(width: min(desired.width, maximumWidth), height: min(desired.height, maximumHeight))
    }

    static func height(for size: PanelCardSize) -> CGFloat {
        switch size {
        case .compact: return 70
        case .regular: return 150
        case .large: return 310
        }
    }

    static func height(for appearance: PanelAppearance) -> CGFloat {
        let rows = span(for: appearance).rows
        return CGFloat(rows) * halfRowHeight + CGFloat(rows - 1) * spacing
    }

    private static func span(for appearance: PanelAppearance) -> (columns: Int, rows: Int) {
        switch appearance.size {
        case .compact: return (1, 1)
        case .regular: return (1, 2)
        case .large: return appearance.largeOrientation == .horizontal ? (2, 2) : (1, 4)
        }
    }

    static func supportsHistory(_ metric: MetricID) -> Bool {
        [.cpu, .memory, .download, .upload].contains(metric)
    }
}
