import XCTest
import AppKit
import GlimpseCore
@testable import GlimpseApp

final class OrganizationDropTests: XCTestCase {
    func testDroppingOnRightHalfOfNextMeterMovesItAfterThatMeter() {
        var settings = AppSettings()
        let original = settings.columns
        XCTAssertTrue(OrganizationDrop.apply(.column(original[0].id), target: .column(original[1].id), edge: .after, settings: &settings))
        XCTAssertEqual(settings.columns, [original[1], original[0], original[2]])
    }

    func testPanelDropUsesBothSidesAndCanAppend() {
        var settings = AppSettings()
        settings.panelMetrics = [.cpu, .memory, .download]
        let ids = settings.panels.map(\.id)
        XCTAssertTrue(OrganizationDrop.apply(.panel(ids[0]), target: .panel(ids[1]), edge: .after, settings: &settings))
        XCTAssertEqual(settings.panelMetrics, [.memory, .cpu, .download])
        XCTAssertTrue(OrganizationDrop.apply(.panel(ids[2]), target: .panel(ids[1]), edge: .before, settings: &settings))
        XCTAssertEqual(settings.panelMetrics, [.download, .memory, .cpu])
        XCTAssertTrue(OrganizationDrop.apply(.panel(ids[2]), target: nil, edge: .after, settings: &settings))
        XCTAssertEqual(settings.panelMetrics, [.memory, .cpu, .download])
    }

    func testDuplicateNetworkPanelsKeepTheirIndependentConfigurationWhenMoved() {
        var settings = AppSettings()
        let wifi = PanelConfiguration(metric: .download, networkInterface: "en0")
        let ethernet = PanelConfiguration(metric: .download, networkInterface: "en1")
        settings.panels = [wifi, ethernet]
        XCTAssertTrue(OrganizationDrop.apply(.panel(wifi.id), target: .panel(ethernet.id), edge: .after, settings: &settings))
        XCTAssertEqual(settings.panels, [ethernet, wifi])
    }

    func testInvalidAndSelfDropsDoNotChangeSettings() {
        var settings = AppSettings()
        let original = settings
        XCTAssertFalse(OrganizationDrop.apply(.panel(settings.panels[0].id), target: .column(settings.columns[0].id), edge: .before, settings: &settings))
        XCTAssertFalse(OrganizationDrop.apply(.panel(settings.panels[0].id), target: .panel(settings.panels[0].id), edge: .after, settings: &settings))
        XCTAssertFalse(OrganizationDrop.apply(.column(UUID()), target: nil, edge: .after, settings: &settings))
        XCTAssertEqual(settings.columns, original.columns)
        XCTAssertEqual(settings.panelMetrics, original.panelMetrics)
    }

    func testNativePasteboardRoundTripRejectsOtherOrganizersAndExternalText() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let payload = OrganizationDragPayload.column(UUID())
        board.writeObjects([payload.pasteboardItem])
        XCTAssertEqual(OrganizationDragPayload.read(from: board, kind: .column), payload)
        XCTAssertNil(OrganizationDragPayload.read(from: board, kind: .panel))
        board.clearContents()
        board.setString(payload.text, forType: .string)
        XCTAssertNil(OrganizationDragPayload.read(from: board, kind: .column))
    }
}
