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
        let first = sample(upload: 100, download: 200, displayName: "First connection")
        let second = sample(upload: 100, download: 200, displayName: "Second connection")
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
        let snapshot = sample(upload: 1_200_000, download: 8_800_000)
        for (name, appearance, width, height) in [
            ("compact", PanelAppearance(size: .compact), 156.0, 70.0),
            ("regular", PanelAppearance(), 156.0, 150.0),
            ("large-vertical", PanelAppearance(size: .large, showsConnectionDetails: true), 156.0, 310.0),
            ("large-horizontal", PanelAppearance(size: .large, largeOrientation: .horizontal, showsConnectionDetails: true), 322.0, 150.0)
        ] {
            let panel = PanelConfiguration(metric: .download, isCombinedNetwork: true, networkInterface: "en0", appearance: appearance)
            try save(render(panel, snapshot: snapshot, width: width, height: height), name: "card-\(name).png")
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

    private func sample(upload: Double?, download: Double?, displayName: String = "Wi-Fi") -> Snapshot {
        Snapshot(timestamp: 1, networkReadings: [
            "en0": NetworkInterfaceReading(identity: "en0:1", name: "en0",
                                            download: MetricReading(value: download, detail: "Measured rate", timestamp: 1),
                                            upload: MetricReading(value: upload, detail: "Measured rate", timestamp: 1))
        ], interfaceDetails: [
            NetworkInterfaceInfo(name: "en0", displayName: displayName, kind: "Wi-Fi", isUp: true, isRunning: true,
                                 ipv4Addresses: ["192.0.2.12"], ipv6Addresses: ["2001:db8::12"],
                                 dnsServers: ["192.0.2.1"], searchDomains: ["example.test"])
        ], automaticNetworkInterface: "en0")
    }
}
