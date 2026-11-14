import XCTest
@testable import GlimpseCore

final class NetworkHistoryTests: XCTestCase {
    private func sample(_ time: Double, _ rates: [(String, String, Double)]) -> Snapshot {
        Snapshot(timestamp: time, networkReadings: Dictionary(uniqueKeysWithValues: rates.map { name, identity, value in
            (name, NetworkInterfaceReading(identity: identity, name: name,
                download: MetricReading(value: value, detail: "", timestamp: time),
                upload: MetricReading(value: value / 2, detail: "", timestamp: time)))
        }), automaticNetworkInterface: rates.first?.0)
    }

    func testInterfacesAndRecreatedDevicesNeverShareHistory() {
        var history = NetworkHistory()
        let first = sample(1, [("en0", "en0:1", 100), ("en1", "en1:2", 900)])
        history.append(first)
        XCTAssertEqual(history.points(for: .download, interface: "en0", snapshot: first).compactMap(\.value), [100])
        XCTAssertEqual(history.points(for: .download, interface: "en1", snapshot: first).compactMap(\.value), [900])
        let replaced = sample(2, [("en0", "en0:9", 50)])
        history.append(replaced)
        XCTAssertEqual(history.points(for: .download, interface: nil, snapshot: replaced).compactMap(\.value), [50])
    }

    func testCollectionGapsBreakLinesAndRetentionRemainsBounded() {
        var history = NetworkHistory()
        history.append(sample(1, [("en0", "en0:1", 100)]))
        history.append(sample(2, []))
        var latest = sample(3, [("en0", "en0:1", 300)])
        history.append(latest)
        XCTAssertEqual(history.points(for: .download, interface: "en0", snapshot: latest).map(\.value), [100, nil, 300])
        for time in 4...700 {
            latest = sample(Double(time), [("en0", "en0:1", Double(time))])
            history.append(latest)
        }
        let points = history.points(for: .download, interface: "en0", snapshot: latest)
        XCTAssertLessThanOrEqual(points.count, 600)
        XCTAssertGreaterThanOrEqual(points.first?.timestamp ?? 0, 400)
    }
}
