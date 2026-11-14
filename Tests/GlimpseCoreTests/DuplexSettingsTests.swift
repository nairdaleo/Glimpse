import XCTest
@testable import GlimpseCore

final class DuplexSettingsTests: XCTestCase {
    func testCombinedConfigurationUsesNetworkThresholdUnitsRegardlessOfBackingMetric() throws {
        let data = Data(#"{"columns":[{"metric":"cpu","colour":"pink","warningThreshold":750000,"criticalThreshold":1200000,"isCombinedNetwork":true,"secondaryColour":"purple"}]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.columns[0].metric, .download)
        XCTAssertEqual(settings.columns[0].warningThreshold, 750_000)
        XCTAssertEqual(settings.columns[0].criticalThreshold, 1_200_000)
    }

    func testLegacyColumnsKeepIndividualMeaningAndGainSafeDefaults() throws {
        let legacy = Data(#"{"columns":[{"metric":"upload","colour":"orange","warningThreshold":500000,"criticalThreshold":1000000}]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        let column = settings.columns[0]
        XCTAssertFalse(column.isCombinedNetwork)
        XCTAssertEqual(column.secondaryColour, .blue)
        XCTAssertEqual(column.requiredMetrics, [.upload])
        XCTAssertEqual(column.displayTitle, "Upload")
        XCTAssertEqual(column.warningThreshold, 500_000)
        XCTAssertEqual(column.criticalThreshold, 1_000_000)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.columns, settings.columns)
        XCTAssertTrue(AppSettings().columns.allSatisfy { !$0.isCombinedNetwork })
    }

    func testMalformedNewFieldsRetainTheLegacyScalarConfiguration() throws {
        let data = Data(#"{"columns":[{"metric":"memory","colour":"pink","isCombinedNetwork":"invalid","secondaryColour":"futureColour"}]}"#.utf8)
        let column = try JSONDecoder().decode(AppSettings.self, from: data).columns[0]
        XCTAssertFalse(column.isCombinedNetwork)
        XCTAssertEqual(column.secondaryColour, .blue)
        XCTAssertEqual(column.requiredMetrics, [.memory])
        XCTAssertEqual(column.displayTitle, "Memory")
    }

    func testDuplexIdentityColoursAndModeSurviveReorderingAndSerialization() throws {
        var settings = AppSettings()
        let duplex = ColumnConfiguration(metric: .thermal, colour: .orange, warningThreshold: 750_000, criticalThreshold: 1_200_000, id: UUID(), isCombinedNetwork: true, secondaryColour: .purple)
        settings.columns.append(duplex)
        settings = settings.validated()
        let target = settings.columns[0].id
        XCTAssertTrue(WidgetOrganization.moveColumn(in: &settings, id: duplex.id, before: target))
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.columns, settings.columns)
        let first = restored.columns[0]
        XCTAssertEqual(first.id, duplex.id)
        XCTAssertTrue(first.isCombinedNetwork)
        XCTAssertEqual(first.metric, .download)
        XCTAssertEqual(first.colour, .orange)
        XCTAssertEqual(first.secondaryColour, .purple)
        XCTAssertEqual(first.displayTitle, "Upload / Download")
        XCTAssertEqual(first.requiredMetrics, [.upload, .download])
        XCTAssertEqual(first.warningThreshold, 750_000)
        XCTAssertEqual(first.criticalThreshold, 1_200_000)
    }
}
