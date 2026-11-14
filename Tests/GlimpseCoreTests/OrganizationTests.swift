import XCTest
@testable import GlimpseCore

final class OrganizationTests: XCTestCase {
    func testValidationPreservesOneColumnAndAllowsEightWithoutPadding() {
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .battery, colour: .pink, warningThreshold: 20, criticalThreshold: 10, thresholdDirection: .below)]
        let one = settings.validated()
        XCTAssertEqual(one.columns.count, 1)
        XCTAssertEqual(one.columns[0].metric, .battery)
        XCTAssertEqual(one.columns[0].warningThreshold, 20)
        settings.columns = Array(repeating: settings.columns[0], count: 10)
        XCTAssertEqual(settings.validated().columns.count, 8)
    }

    func testEmptyColumnListRepairsToOneReachableCPUMeter() {
        var settings = AppSettings()
        settings.columns = []
        let repaired = settings.validated()
        XCTAssertEqual(repaired.columns.count, 1)
        XCTAssertEqual(repaired.columns.first?.metric, .cpu)
    }
    func testLegacySettingsPreserveColumnsAndPersistNewIdentities() throws {
        let legacy = Data(#"{"columns":[{"metric":"battery","colour":"pink","warningThreshold":20,"criticalThreshold":10,"thresholdDirection":"below"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(decoded.columns.count, 1)
        XCTAssertEqual(restored.columns, decoded.columns)
        XCTAssertEqual(restored.columns[0].warningThreshold, 20)
        XCTAssertEqual(restored.columnScale, 1)
        XCTAssertEqual(restored.panelMetrics, MetricID.allCases)
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(missing.columns.map(\.metric), [.cpu, .memory, .download])
    }

    func testValidationRepairsIdentityCollisionsAndKeepsPanelOrderAndEmptyVisibility() throws {
        var settings = AppSettings()
        settings.columns = Array(repeating: ColumnConfiguration(metric: .battery, colour: .orange), count: 3)
        let firstID = settings.columns[0].id
        settings.panelMetrics = [.thermal, .cpu, .thermal, .disk, .cpu]
        settings.columnScale = 5
        let repaired = settings.validated()
        XCTAssertEqual(Set(repaired.columns.map(\.id)).count, 3)
        XCTAssertEqual(repaired.columns[0].id, firstID)
        XCTAssertEqual(repaired.panelMetrics, [.thermal, .cpu, .disk])
        XCTAssertEqual(repaired.columnScale, 1.5)
        XCTAssertEqual(repaired.validated().columns, repaired.columns)
        settings.columnScale = 0
        XCTAssertEqual(settings.validated().columnScale, 0.75)
        settings.columnScale = .nan
        XCTAssertEqual(settings.validated().columnScale, 1)
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"panelMetrics":[],"columns":[]}"#.utf8))
        XCTAssertTrue(empty.panelMetrics.isEmpty)
        XCTAssertEqual(empty.columns.count, 1)
        let future = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"panelMetrics":["thermal","future","cpu","thermal"]}"#.utf8))
        XCTAssertEqual(future.panelMetrics, [.thermal, .cpu])
    }

    func testMovingColumnsPreservesCompleteConfigurationAndRejectsInvalidDrags() {
        var settings = AppSettings()
        settings.columns[0].warningThreshold = 70
        settings.columns[0].criticalThreshold = 90
        let original = settings.columns
        XCTAssertTrue(WidgetOrganization.moveColumn(in: &settings, id: original[2].id, before: original[0].id))
        XCTAssertEqual(settings.columns, [original[2], original[0], original[1]])
        XCTAssertTrue(WidgetOrganization.moveColumn(in: &settings, id: original[2].id, before: nil))
        XCTAssertEqual(settings.columns, [original[0], original[1], original[2]])
        XCTAssertFalse(WidgetOrganization.moveColumn(in: &settings, id: UUID(), before: original[0].id))
        XCTAssertFalse(WidgetOrganization.moveColumn(in: &settings, id: original[0].id, before: UUID()))
        XCTAssertFalse(WidgetOrganization.moveColumn(in: &settings, id: original[0].id, before: original[0].id))
        XCTAssertEqual(settings.columns, original)
    }

    func testAddAndRemoveProtectReachabilityAndEightColumnLimit() {
        var settings = AppSettings()
        let original = settings.columns
        for _ in 0..<5 { XCTAssertNotNil(WidgetOrganization.addColumn(to: &settings, metric: .battery)) }
        XCTAssertNil(WidgetOrganization.addColumn(to: &settings, metric: .upload))
        XCTAssertEqual(settings.columns.count, 8)
        XCTAssertEqual(Array(settings.columns.prefix(3)), original)
        XCTAssertEqual(Set(settings.columns.map(\.id)).count, 8)
        while settings.columns.count > 1 { XCTAssertTrue(WidgetOrganization.removeColumn(from: &settings, id: settings.columns.last!.id)) }
        XCTAssertFalse(WidgetOrganization.removeColumn(from: &settings, id: settings.columns[0].id))
        XCTAssertFalse(WidgetOrganization.removeColumn(from: &settings, id: UUID()))
        XCTAssertEqual(settings.columns, [original[0]])
    }

    func testPanelOrganizationAddsAtEndAndNeverChangesIconColumns() {
        var settings = AppSettings()
        let columns = settings.columns
        settings.panelMetrics = [.cpu, .memory, .download]
        XCTAssertTrue(WidgetOrganization.movePanel(in: &settings, metric: .download, before: .cpu))
        XCTAssertEqual(settings.panelMetrics, [.download, .cpu, .memory])
        XCTAssertFalse(WidgetOrganization.movePanel(in: &settings, metric: .battery, before: .cpu))
        XCTAssertFalse(WidgetOrganization.movePanel(in: &settings, metric: .cpu, before: .battery))
        XCTAssertFalse(WidgetOrganization.movePanel(in: &settings, metric: .cpu, before: .cpu))
        WidgetOrganization.setPanel(in: &settings, metric: .cpu, visible: false)
        WidgetOrganization.setPanel(in: &settings, metric: .cpu, visible: true)
        WidgetOrganization.setPanel(in: &settings, metric: .cpu, visible: true)
        XCTAssertEqual(settings.panelMetrics, [.download, .memory, .cpu])
        XCTAssertTrue(WidgetOrganization.movePanel(in: &settings, metric: .download, before: nil))
        XCTAssertEqual(settings.panelMetrics, [.memory, .cpu, .download])
        for metric in MetricID.allCases { WidgetOrganization.setPanel(in: &settings, metric: metric, visible: false) }
        XCTAssertTrue(settings.panelMetrics.isEmpty)
        XCTAssertEqual(settings.columns, columns)
    }
}
