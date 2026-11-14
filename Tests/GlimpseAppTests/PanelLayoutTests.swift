import XCTest
import GlimpseCore
@testable import GlimpseApp

final class PanelLayoutTests: XCTestCase {
    func testMoreCardsPerRowMakesTheDropdownWiderAndShorter() {
        var settings = AppSettings()
        settings.panelColumns = 1
        let tall = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        settings.panelColumns = 8
        let wide = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(tall.columns, 1)
        XCTAssertEqual(wide.columns, settings.panelMetrics.count)
        XCTAssertGreaterThan(wide.size.width, tall.size.width)
        XCTAssertLessThan(wide.size.height, tall.size.height)
    }

    func testPerCardSizeAndScreenBoundsPreserveRequestedGrid() {
        var settings = AppSettings()
        settings.panelMetrics = [.cpu]
        settings.panelAppearances[MetricID.cpu.rawValue] = PanelAppearance(size: .compact)
        let compact = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        settings.panelAppearances[MetricID.cpu.rawValue] = PanelAppearance(size: .large)
        let large = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertGreaterThan(try! XCTUnwrap(large.cardHeights[.cpu]), try! XCTUnwrap(compact.cardHeights[.cpu]))
        XCTAssertGreaterThan(large.size.height, compact.size.height)

        settings.panelMetrics = MetricID.allCases
        settings.panelColumns = 8
        settings.panelCardWidth = 240
        let bounded = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 500, height: 300))
        XCTAssertLessThanOrEqual(bounded.size.width, 500)
        XCTAssertLessThanOrEqual(bounded.size.height, 300)
        XCTAssertEqual(bounded.columns, MetricID.allCases.count)
        XCTAssertGreaterThan(bounded.gridWidth, bounded.size.width)
    }

    func testEmptyPanelSetStillProvidesReachableSettingsAndNoSpuriousCards() {
        var settings = AppSettings()
        settings.panelMetrics = []
        let empty = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 500, height: 500))
        XCTAssertTrue(empty.cardHeights.isEmpty)
        XCTAssertGreaterThan(empty.size.width, 0)
        XCTAssertGreaterThan(empty.size.height, 0)
    }

    func testTwoCompactPanelsStackIntoOneRegularFootprint() {
        var settings = AppSettings()
        settings.panelColumns = 1
        settings.panels = [PanelConfiguration(metric: .cpu, appearance: PanelAppearance(size: .regular))]
        let regular = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        settings.panels = [.init(metric: .cpu, appearance: .init(size: .compact)), .init(metric: .memory, appearance: .init(size: .compact))]
        let compact = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(compact.gridHeight, regular.gridHeight)
        XCTAssertEqual(compact.gridHeight, 150)
        XCTAssertEqual(compact.gridWidth, regular.gridWidth)
    }

    func testCompactPairsShareARegularSlotBeforeMovingToTheNextColumn() throws {
        var settings = AppSettings()
        settings.panelColumns = 2
        settings.panels = [.init(metric: .cpu, appearance: .init(size: .compact)),
                           .init(metric: .memory, appearance: .init(size: .compact)),
                           .init(metric: .download)]
        let layout = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(layout.placements[settings.panels[0].id], CGRect(x: 0, y: 0, width: 156, height: 70))
        XCTAssertEqual(layout.placements[settings.panels[1].id], CGRect(x: 0, y: 80, width: 156, height: 70))
        XCTAssertEqual(layout.placements[settings.panels[2].id], CGRect(x: 166, y: 0, width: 156, height: 150))
        XCTAssertEqual(layout.gridWidth, 322)
        XCTAssertEqual(layout.gridHeight, 150)
        settings.panels.removeLast()
        settings.panelColumns = 8
        let pairOnly = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(pairOnly.columns, 1)
        XCTAssertEqual(pairOnly.gridWidth, 156)
        XCTAssertEqual(pairOnly.gridHeight, 150)
    }

    func testCompactCardsStackAsSeparateHalfSlotsWithoutMerging() throws {
        var settings = AppSettings()
        settings.panelColumns = 1
        settings.panels = [.init(metric: .disk, appearance: .init(size: .compact)),
                           .init(metric: .battery, appearance: .init(size: .compact))]
        let layout = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(layout.placements[settings.panels[0].id], CGRect(x: 0, y: 0, width: 156, height: 70))
        XCTAssertEqual(layout.placements[settings.panels[1].id], CGRect(x: 0, y: 80, width: 156, height: 70))
        XCTAssertEqual(layout.gridHeight, 150)
    }

    func testLargeOrientationsUseTwoRegularSlotsWithoutChangingTheChosenOrientation() {
        var settings = AppSettings()
        settings.panelColumns = 1
        settings.panelCardWidth = 190
        let panel = PanelConfiguration(metric: .cpu, appearance: .init(size: .large, largeOrientation: .vertical))
        settings.panels = [panel]
        let vertical = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(vertical.placements[panel.id], CGRect(x: 0, y: 0, width: 190, height: 310))
        XCTAssertEqual(vertical.gridWidth, 190)
        XCTAssertEqual(vertical.gridHeight, 310)
        settings.panels[0].appearance.largeOrientation = .horizontal
        let horizontal = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(horizontal.columns, 2)
        XCTAssertEqual(horizontal.placements[panel.id], CGRect(x: 0, y: 0, width: 390, height: 150))
        XCTAssertEqual(horizontal.gridWidth, 390)
        XCTAssertEqual(horizontal.gridHeight, 150)
        XCTAssertEqual(settings.panelColumns, 1)
        XCTAssertEqual(settings.panels[0].appearance.largeOrientation, .horizontal)
    }

    func testMixedSpansNeverOverlapOrBackfillEarlierSlots() throws {
        var settings = AppSettings()
        settings.panelColumns = 3
        let appearances: [PanelAppearance] = [.init(size: .compact), .init(size: .large), .init(size: .compact),
                                               .init(size: .regular), .init(size: .large, largeOrientation: .horizontal)]
        settings.panels = (0..<32).map { .init(metric: .download, appearance: appearances[$0 % appearances.count]) }
        let layout = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 4000, height: 4000))
        XCTAssertEqual(layout.placements.count, settings.panels.count)
        let bounds = CGRect(x: 0, y: 0, width: layout.gridWidth, height: layout.gridHeight)
        var previousStart = -1
        let frames = try settings.panels.map { panel -> CGRect in
            let frame = try XCTUnwrap(layout.placements[panel.id])
            XCTAssertTrue(bounds.contains(frame))
            XCTAssertEqual(layout.panelHeights[panel.id], frame.height)
            let halfRow = Int((frame.minY / 80).rounded())
            let column = Int((frame.minX / (layout.cardWidth + 10)).rounded())
            let start = (halfRow / 2) * 6 + column * 2 + halfRow % 2
            XCTAssertGreaterThan(start, previousStart)
            previousStart = start
            if panel.appearance.size != .compact { XCTAssertEqual(halfRow % 2, 0) }
            return frame
        }
        for first in frames.indices {
            for second in frames.indices where second > first { XCTAssertFalse(frames[first].intersects(frames[second])) }
        }
        // The second card advances to column one. Later cards must leave the
        // lower half of the first slot empty rather than moving backwards.
        XCTAssertEqual(frames[1].minX, 166)
        XCTAssertEqual(frames[2].minX, 332)
        XCTAssertFalse(frames.dropFirst(2).contains { $0.minX == 0 && $0.minY == 80 })
    }

    func testScreenClampKeepsWidePlacementAndAllowsScrollingInsteadOfRotating() {
        var settings = AppSettings()
        settings.panelColumns = 1
        settings.panelCardWidth = 240
        settings.panels = [.init(metric: .upload, appearance: .init(size: .large, largeOrientation: .horizontal))]
        let layout = StatusPanelLayout(settings: settings, maximumSize: CGSize(width: 300, height: 200))
        XCTAssertEqual(layout.size.width, 300)
        XCTAssertEqual(layout.size.height, 200)
        XCTAssertEqual(layout.gridWidth, 490)
        XCTAssertEqual(layout.gridHeight, 150)
        XCTAssertEqual(layout.placements[settings.panels[0].id]?.width, 490)
    }
}
