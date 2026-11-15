import XCTest
@testable import GlimpseCore

final class ScreenshotSafeTests: XCTestCase {
    func testReplacesEveryPrivateFieldAndKeepsShape() {
        let real = NetworkInterfaceInfo(name: "en0", displayName: "Wi-Fi", kind: "Wi-Fi", isUp: true, isRunning: true,
                                        ipv4Addresses: ["10.0.0.58"], ipv6Addresses: ["fe80::1426:a9b1", "2a01:4f8::1"], dnsServers: ["10.0.0.1"],
                                        searchDomains: ["home.lan"], subnetMasks: ["255.255.255.0"], routers: ["10.0.0.1"],
                                        macAddress: "86:d5:0c:e2:e1:03", proxies: ["HTTP corp:3128"])
        let safe = Snapshot(timestamp: 1, interfaceDetails: [real]).screenshotSafe.interfaceDetails[0]
        XCTAssertEqual(safe.name, "en0")
        XCTAssertEqual(safe.ipv4Addresses, ["192.0.2.24"])
        XCTAssertEqual(safe.ipv6Addresses.count, 2)
        XCTAssertTrue(safe.ipv6Addresses.allSatisfy { $0.hasPrefix("2001:db8::") })
        XCTAssertEqual(safe.routers, ["192.0.2.1"])
        XCTAssertEqual(safe.dnsServers, ["192.0.2.53"])
        XCTAssertEqual(safe.searchDomains, ["example.com"])
        XCTAssertEqual(safe.macAddress, "02:00:5e:00:53:24")
        XCTAssertEqual(safe.proxies, ["HTTPS proxy.example.com:8080"])
        let text = "\(safe)"
        for secret in ["10.0.0", "fe80", "2a01", "home.lan", "86:d5", "corp"] { XCTAssertFalse(text.contains(secret), secret) }
    }
}
