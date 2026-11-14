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
}
