import XCTest
@testable import GlimpseCore

final class ColourBandsTests: XCTestCase {
    func testHardChangeSwitchesAtEachThreshold() {
        let bands = ColourBands(stops: [.init(threshold: 20, colour: .orange), .init(threshold: 60, colour: .blue)])
        XCTAssertEqual(bands.colour(for: 10, base: .pink).from, .pink)
        XCTAssertEqual(bands.colour(for: 20, base: .pink).from, .orange)
        XCTAssertEqual(bands.colour(for: 59, base: .pink).from, .orange)
        XCTAssertEqual(bands.colour(for: 60, base: .pink).from, .blue)
        XCTAssertEqual(bands.colour(for: 40, base: .pink).fraction, 0)
    }

    func testGradientBlendsFromZeroThroughEachThreshold() {
        let two = ColourBands(stops: [.init(threshold: 50, colour: .blue)], gradient: true)
        let half = two.colour(for: 25, base: .pink)
        XCTAssertEqual(half.from, .pink); XCTAssertEqual(half.to, .blue); XCTAssertEqual(half.fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(two.colour(for: 80, base: .pink).from, .blue)
        let three = ColourBands(stops: [.init(threshold: 20, colour: .orange), .init(threshold: 60, colour: .blue)], gradient: true)
        let upper = three.colour(for: 40, base: .pink)
        XCTAssertEqual(upper.from, .orange); XCTAssertEqual(upper.to, .blue); XCTAssertEqual(upper.fraction, 0.5, accuracy: 1e-9)
    }

    func testBandsRoundTripValidateAndOnlyBatteryKeepsThem() throws {
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .battery, colour: .mint), ColumnConfiguration(metric: .cpu, colour: .mint)]
        settings.columns[0].colourBands = ColourBands(stops: [.init(threshold: 150, colour: .blue), .init(threshold: 10, colour: .orange), .init(threshold: 5, colour: .pink)], gradient: true)
        settings.columns[1].colourBands = ColourBands(stops: ColourBands.defaults(count: 2))
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        let bands = try XCTUnwrap(restored.columns[0].colourBands)
        XCTAssertTrue(bands.gradient)
        XCTAssertEqual(bands.stops.map(\.threshold), [10, 100])
        XCTAssertNil(restored.columns[1].colourBands)
    }

    func testCombinedNetworkDownloadThresholdsSplitFromUpload() throws {
        let legacy = try JSONDecoder().decode(ColumnConfiguration.self, from: Data(#"{"metric":"download","colour":"blue","isCombinedNetwork":true,"warningThreshold":100,"criticalThreshold":200}"#.utf8))
        XCTAssertEqual(legacy.downloadWarningThreshold, 100)
        XCTAssertEqual(legacy.downloadCriticalThreshold, 200)

        var settings = AppSettings()
        var column = ColumnConfiguration(metric: .download, colour: .blue, warningThreshold: 700_000, criticalThreshold: 900_000, isCombinedNetwork: true)
        column.downloadWarningThreshold = 7_000_000
        column.downloadCriticalThreshold = nil
        settings.columns = [column]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).columns[0]
        XCTAssertEqual(restored.warningThreshold, 700_000)
        XCTAssertEqual(restored.downloadWarningThreshold, 7_000_000)
        XCTAssertNil(restored.downloadCriticalThreshold)

        var latch = ThresholdLatch()
        XCTAssertEqual(latch.evaluate(value: 7_500_000, column: restored.downloadThresholdColumn, deadband: 0), .warning)
    }
}
