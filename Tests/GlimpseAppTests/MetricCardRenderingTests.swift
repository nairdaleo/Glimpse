import XCTest
import SwiftUI
import AppKit
import GlimpseCore
@testable import GlimpseApp

final class MetricCardRenderingTests: XCTestCase {
    @MainActor
    func testCompactDuplexKeepsBothReadingsVisibleAtSeventyPoints() throws {
        let panel = PanelConfiguration(metric: .download, isCombinedNetwork: true, networkInterface: "en0",
                                       appearance: PanelAppearance(size: .compact))
        let full = try render(panel, snapshot: sample(upload: 876_000, download: 987_000), width: 120, height: 70)
        let missingUpload = try render(panel, snapshot: sample(upload: nil, download: 987_000), width: 120, height: 70)
        let missingDownload = try render(panel, snapshot: sample(upload: 876_000, download: nil), width: 120, height: 70)
        XCTAssertNotEqual(full, missingUpload, "Changing upload must affect the visible compact card.")
        XCTAssertNotEqual(full, missingDownload, "Changing download must affect the visible compact card.")
        try save(full, name: "card-compact-duplex.png")
    }

    @MainActor
    func testConnectionMetadataOnlyAppearsWhenEnabled() throws {
        var panel = PanelConfiguration(metric: .download, networkInterface: "en0",
                                       appearance: PanelAppearance(size: .large, showsHistory: false))
        let first = sample(upload: 100, download: 200, router: "192.0.2.1")
        let second = sample(upload: 100, download: 200, router: "198.51.100.1")
        XCTAssertEqual(try render(panel, snapshot: first, width: 156, height: 310),
                       try render(panel, snapshot: second, width: 156, height: 310))
        panel.appearance.showsConnectionDetails = true
        XCTAssertNotEqual(try render(panel, snapshot: first, width: 156, height: 310),
                          try render(panel, snapshot: second, width: 156, height: 310))
    }

    @MainActor
    func testActualCardArtifactsForEverySizeAndOrientation() throws {
        guard ProcessInfo.processInfo.environment["GLIMPSE_RENDER_ARTIFACTS"] != nil else {
            throw XCTSkip("Set GLIMPSE_RENDER_ARTIFACTS to export actual card views.")
        }
        var snapshot = sample(upload: 1_200_000, download: 8_800_000)
        snapshot.readings[.disk] = MetricReading(value: 94, detail: "Free: 60.1 GB\n935 GB used of 995 GB", timestamp: 1)
        snapshot.readings[.battery] = MetricReading(value: 95, detail: "On battery\n7 hr 32 min left · 6.7 W draw\nHealth 83% · 320 cycles", timestamp: 1)
        snapshot.readings[.memory] = MetricReading(value: 72, detail: "18.6 GB used of 25.8 GB", timestamp: 1)
        snapshot.readings[.cpu] = MetricReading(value: 23, detail: "User 15% · System 8%", timestamp: 1)
        let sizes: [(String, PanelAppearance, CGFloat, CGFloat)] = [
            ("compact", PanelAppearance(size: .compact), 156, 70),
            ("regular", PanelAppearance(), 156, 150),
            ("large-vertical", PanelAppearance(size: .large), 156, 310),
            ("large-horizontal", PanelAppearance(size: .large, largeOrientation: .horizontal), 322, 150)
        ]
        let kinds: [(String, PanelConfiguration)] = [
            ("duplex", PanelConfiguration(metric: .download, isCombinedNetwork: true, networkInterface: "en0")),
            ("download", PanelConfiguration(metric: .download, networkInterface: "en0")),
            ("disk", PanelConfiguration(metric: .disk)),
            ("battery", PanelConfiguration(metric: .battery)),
            ("memory", PanelConfiguration(metric: .memory)),
            ("cpu", PanelConfiguration(metric: .cpu))
        ]
        for (kind, base) in kinds {
            for (size, appearance, width, height) in sizes {
                for details in base.isNetwork ? [false, true] : [false] {
                    var panel = base
                    panel.appearance = appearance
                    panel.appearance.showsConnectionDetails = details
                    try save(render(panel, snapshot: snapshot, width: width, height: height),
                             name: "card-\(kind)-\(size)\(details ? "-details" : "").png")
                }
            }
        }
    }

    @MainActor
    private func render(_ panel: PanelConfiguration, snapshot: Snapshot, width: CGFloat, height: CGFloat) throws -> Data {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: MetricCardContent(panel: panel, snapshot: snapshot,
                                                           history: MetricHistory(), networkHistory: NetworkHistory(),
                                                           settings: AppSettings(), width: width, height: height)
            .environment(\.colorScheme, .light).background(Color.white))
        view.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(CGFloat(bitmap.pixelsWide) / CGFloat(bitmap.pixelsHigh), width / height, accuracy: 0.01)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func save(_ data: Data, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["GLIMPSE_RENDER_ARTIFACTS"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try data.write(to: url.appendingPathComponent(name))
    }

    private func sample(upload: Double?, download: Double?, router: String = "192.0.2.1") -> Snapshot {
        Snapshot(timestamp: 1, networkReadings: [
            "en0": NetworkInterfaceReading(identity: "en0:1", name: "en0",
                                            download: MetricReading(value: download, detail: "Measured rate", timestamp: 1),
                                            upload: MetricReading(value: upload, detail: "Measured rate", timestamp: 1))
        ], interfaceDetails: [
            NetworkInterfaceInfo(name: "en0", displayName: "Wi-Fi", kind: "Wi-Fi", isUp: true, isRunning: true,
                                 ipv4Addresses: ["192.0.2.12"], ipv6Addresses: ["2001:db8::12"],
                                 dnsServers: ["192.0.2.1"], searchDomains: ["example.test"],
                                 subnetMasks: ["255.255.255.0"], routers: [router], macAddress: "a4:83:e7:12:34:56",
                                 proxies: ["HTTPS proxy.example.test:8080"])
        ], automaticNetworkInterface: "en0")
    }
}
