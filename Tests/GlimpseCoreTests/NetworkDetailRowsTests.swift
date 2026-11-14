import XCTest
@testable import GlimpseCore

final class NetworkDetailRowsTests: XCTestCase {
    private let info = NetworkInterfaceInfo(name: "en0", displayName: "Wi-Fi", kind: "Wi-Fi", isUp: true, isRunning: true,
                                            ipv4Addresses: ["192.0.2.12"], dnsServers: ["192.0.2.1", "192.0.2.2"],
                                            subnetMasks: ["255.255.255.0"], routers: ["192.0.2.1"], macAddress: "a4:83:e7:12:34:56")

    func testRowsFollowFieldOrderWithContinuationRowsAndPlaceholders() {
        let rows = info.detailRows()
        XCTAssertEqual(rows.map(\.label), ["Status", "IPv4", "Mask", "Router", "IPv6", "DNS", "", "Search", "MAC"])
        XCTAssertEqual(rows.first { $0.label == "IPv6" }?.value, "—")
        XCTAssertFalse(rows.contains { $0.label == "Proxy" }, "Proxy appears only when configured.")
    }

    func testSelectedFieldsOnlyAndProxyWhenSet() {
        var withProxy = info
        withProxy.proxies = ["HTTPS proxy.example.test:8080"]
        XCTAssertEqual(withProxy.detailRows([.router, .proxy]).map(\.value), ["192.0.2.1", "HTTPS proxy.example.test:8080"])
    }

    func testAutomaticFitAddsWholeFieldsInUsefulnessOrder() {
        XCTAssertEqual(info.fittedRows(capacity: 1).map(\.label), ["IPv4"])
        XCTAssertEqual(info.fittedRows(capacity: 2).map(\.label), ["IPv4", "Router"])
        // DNS has two servers: skipped at 3 rows, so Mask fills the slot instead.
        XCTAssertEqual(info.fittedRows(capacity: 3).map(\.label), ["IPv4", "Router", "Mask"])
        XCTAssertEqual(info.fittedRows(capacity: 4).map(\.label), ["IPv4", "Router", "DNS", ""])
        XCTAssertTrue(info.fittedRows(capacity: 0).isEmpty)
    }

    func testConnectionFieldsDefaultToAutomaticAndRoundTrip() throws {
        XCTAssertNil(PanelAppearance().connectionFields)
        let earlierAll = try JSONDecoder().decode(PanelAppearance.self, from: Data(#"{"connectionFields":["status","ipv4","subnetMask","router","ipv6","dns","searchDomains","mac","proxy"]}"#.utf8))
        XCTAssertNil(earlierAll.connectionFields, "The earlier all-fields default reads as automatic.")
        let chosen = PanelAppearance(connectionFields: [.ipv4, .router])
        XCTAssertEqual(try JSONDecoder().decode(PanelAppearance.self, from: JSONEncoder().encode(chosen)).connectionFields, [.ipv4, .router])
        let future = try JSONDecoder().decode(PanelAppearance.self, from: Data(#"{"connectionFields":["mac","futureField"]}"#.utf8))
        XCTAssertEqual(future.connectionFields, [.mac])
    }
}
