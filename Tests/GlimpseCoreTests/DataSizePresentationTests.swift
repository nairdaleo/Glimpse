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
}
