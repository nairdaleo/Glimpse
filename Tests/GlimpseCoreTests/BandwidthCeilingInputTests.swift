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
}
