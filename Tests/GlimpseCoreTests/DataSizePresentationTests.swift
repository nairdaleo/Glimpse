import XCTest
@testable import GlimpseCore

final class DataSizePresentationTests: XCTestCase {
    func testSIAndIECPrefixes() {
        XCTAssertEqual(DataSizePresentation.string(bytes: 61_000_000_000, units: .si), "61.0 GB")
        XCTAssertEqual(DataSizePresentation.string(bytes: 16 * 1_073_741_824, units: .iec), "16.0 GiB")
        XCTAssertEqual(DataSizePresentation.string(bytes: 994_000_000_000, units: .si), "994 GB")
        XCTAssertEqual(DataSizePresentation.string(bytes: 512, units: .iec), "512 B")
    }

    func testCapacityUnitsDefaultAndRoundTrip() throws {
        XCTAssertEqual(AppSettings().capacityUnits, .si)
        var settings = AppSettings()
        settings.capacityUnits = .iec
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.capacityUnits, .iec)
    }

    func testBandwidthUnitsAreIndependentAndFormatRates() throws {
        var settings = AppSettings()
        settings.bandwidthUnits = .iec
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.bandwidthUnits, .iec)
        XCTAssertEqual(restored.capacityUnits, .si)
        XCTAssertEqual(MetricPresentation.formatted(value: 2_097_152, metric: .download, units: .iec), "2.0 MiB/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 2_000_000, metric: .download, units: .si), "2.0 MB/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 131_072, metric: .upload, bits: true, units: .iec), "1.0 Mib/s")
        XCTAssertEqual(BandwidthCeilingInput.bytesPerSecond(displayValue: 1, bits: false, units: .iec), 1_048_576)
        XCTAssertEqual(BandwidthCeilingInput.unit(bits: true, units: .iec), "Mib/s")
    }
}
