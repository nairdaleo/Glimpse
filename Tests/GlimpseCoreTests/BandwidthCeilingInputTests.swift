import XCTest
@testable import GlimpseCore

final class BandwidthCeilingInputTests: XCTestCase {
    func testSameStoredCeilingDisplaysAsMegabytesOrMegabitsWithMatchingUnits() {
        XCTAssertEqual(BandwidthCeilingInput.displayValue(bytesPerSecond: 12_500_000, bits: false), 12.5)
        XCTAssertEqual(BandwidthCeilingInput.unit(bits: false), "MB/s")
        XCTAssertEqual(BandwidthCeilingInput.displayValue(bytesPerSecond: 12_500_000, bits: true), 100)
        XCTAssertEqual(BandwidthCeilingInput.unit(bits: true), "Mb/s")
    }

    func testEditingMegabitsStoresBytesAndPreservesTheActualMeterScale() {
        let bytes = BandwidthCeilingInput.bytesPerSecond(displayValue: 200, bits: true)
        XCTAssertEqual(bytes, 25_000_000)
        XCTAssertEqual(BandwidthCeilingInput.displayValue(bytesPerSecond: bytes, bits: false), 25)
        XCTAssertEqual(MetricPresentation.normalized(value: 12_500_000, metric: .download, networkCeiling: bytes), 0.5)
        XCTAssertEqual(BandwidthCeilingInput.bytesPerSecond(displayValue: 12.5, bits: false), 12_500_000)
    }

    func testChangingUnitsAndRoundTrippingFractionalValuesDoesNotRescaleStoredTraffic() {
        let original = 1_234_567.89
        for bits in [false, true, false, true] {
            let displayed = BandwidthCeilingInput.displayValue(bytesPerSecond: original, bits: bits)
            let restored = BandwidthCeilingInput.bytesPerSecond(displayValue: displayed, bits: bits)
            XCTAssertEqual(restored, original, accuracy: 0.000001)
        }
    }

    func testUploadCeilingIsIndependentAndLegacySettingsInheritTheSharedCeiling() throws {
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"networkCeiling":9375000}"#.utf8))
        XCTAssertEqual(legacy.uploadCeiling, 9_375_000)
        var settings = AppSettings()
        settings.networkCeiling = BandwidthCeilingInput.bytesPerSecond(displayValue: 75, bits: true)
        settings.uploadCeiling = BandwidthCeilingInput.bytesPerSecond(displayValue: 7.5, bits: true)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.networkCeiling(for: .download), 9_375_000)
        XCTAssertEqual(restored.networkCeiling(for: .upload), 937_500)
        XCTAssertEqual(MetricPresentation.normalized(value: 468_750, metric: .upload, networkCeiling: restored.networkCeiling(for: .upload)), 0.5)
        settings.uploadCeiling = .nan
        XCTAssertEqual(settings.validated().uploadCeiling, settings.networkCeiling)
    }
}
