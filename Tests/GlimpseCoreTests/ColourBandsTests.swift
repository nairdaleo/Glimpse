import XCTest
@testable import GlimpseCore

final class ColourBandsTests: XCTestCase {
    func testHardChangePicksTheBandAndFallsBackToTheMeterColour() {
        let bands = ColourBands(high: .blue, middle: nil, low: .pink, highThreshold: 60, lowThreshold: 20)
        XCTAssertEqual(bands.colour(for: 80, base: .mint).from, .blue)
        XCTAssertEqual(bands.colour(for: 60, base: .mint).from, .blue)
        XCTAssertEqual(bands.colour(for: 40, base: .mint).from, .mint)
        XCTAssertEqual(bands.colour(for: 20, base: .mint).from, .pink)
        XCTAssertEqual(bands.colour(for: 40, base: .mint).fraction, 0)
    }

    func testGradientBlendsBetweenAnchors() {
        var bands = ColourBands(style: .gradient, high: .blue, middle: nil, low: .pink, highThreshold: 60, lowThreshold: 20)
        let mid = bands.colour(for: 40, base: .mint)
        XCTAssertEqual(mid.from, .pink); XCTAssertEqual(mid.to, .blue); XCTAssertEqual(mid.fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(bands.colour(for: 10, base: .mint).from, .pink)
        XCTAssertEqual(bands.colour(for: 90, base: .mint).from, .blue)
        bands.middle = .orange
        let lower = bands.colour(for: 30, base: .mint)
        XCTAssertEqual(lower.from, .pink); XCTAssertEqual(lower.to, .orange); XCTAssertEqual(lower.fraction, 0.5, accuracy: 1e-9)
    }

    func testBandsRoundTripAndOnlyBatteryKeepsThem() throws {
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .battery, colour: .mint), ColumnConfiguration(metric: .cpu, colour: .mint)]
        settings.columns[0].colourBands = ColourBands(style: .gradient, middle: nil, highThreshold: 10, lowThreshold: 150)
        settings.columns[1].colourBands = ColourBands()
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        let bands = try XCTUnwrap(restored.columns[0].colourBands)
        XCTAssertEqual(bands.style, .gradient)
        XCTAssertNil(bands.middle)
        XCTAssertEqual(bands.lowThreshold, 10)
        XCTAssertEqual(bands.highThreshold, 100)
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
