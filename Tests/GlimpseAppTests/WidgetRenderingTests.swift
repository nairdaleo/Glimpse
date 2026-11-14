import XCTest
import AppKit
import GlimpseCore
@testable import GlimpseApp

final class WidgetRenderingTests: XCTestCase {
    func testNetworkMeterUsesItsOwnInterfaceRatherThanGlobalReadout() throws {
        var settings = AppSettings()
        settings.networkCeiling = 100
        settings.columns = [ColumnConfiguration(metric: .download, colour: .blue, networkInterface: "en1")]
        let snapshot = Snapshot(timestamp: 1, readings: [.download: MetricReading(value: 0, detail: "global", timestamp: 1)], networkReadings: [
            "en0": NetworkInterfaceReading(identity: "en0:1", name: "en0", download: MetricReading(value: 0, detail: "", timestamp: 1), upload: MetricReading(value: 0, detail: "", timestamp: 1)),
            "en1": NetworkInterfaceReading(identity: "en1:2", name: "en1", download: MetricReading(value: 100, detail: "", timestamp: 1), upload: MetricReading(value: 0, detail: "", timestamp: 1))
        ], automaticNetworkInterface: "en0")
        func centreColour() throws -> NSColor {
            let image = MeterImage.make(settings: settings, snapshot: snapshot, levels: [.normal], appearance: NSAppearance(named: .aqua)!)
            var rect = CGRect(origin: .zero, size: image.size)
            let cg = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cg)
            let track = MeterImage.layout(settings: settings, snapshot: snapshot).meterRects[0]
            let scale = CGFloat(bitmap.pixelsWide) / image.size.width
            return try XCTUnwrap(bitmap.colorAt(x: Int(track.midX * scale), y: Int(track.midY * scale))?.usingColorSpace(.sRGB))
        }
        let explicit = try centreColour()
        settings.columns[0].networkInterface = nil
        let automatic = try centreColour()
        XCTAssertGreaterThan(abs(explicit.blueComponent - automatic.blueComponent) + abs(explicit.redComponent - automatic.redComponent), 0.2)
    }

    func testOneToEightMetersAndScaleChangeWidthWithoutChangingVerticalAlignment() {
        let one = StatusWidgetLayout(columnCount: 1, scale: 1, showBandwidth: false)
        let eight = StatusWidgetLayout(columnCount: 8, scale: 1.5, showBandwidth: false)
        XCTAssertEqual(one.meterRects.count, 1)
        XCTAssertEqual(eight.meterRects.count, 8)
        XCTAssertGreaterThan(eight.size.width, one.size.width)
        XCTAssertEqual(one.meterRects[0].midY, eight.meterRects[7].midY)
        XCTAssertGreaterThan(eight.meterRects[0].width, one.meterRects[0].width)
        for rect in eight.meterRects { XCTAssertTrue(CGRect(origin: .zero, size: eight.size).contains(rect)) }
        for index in 1..<8 { XCTAssertLessThan(eight.meterRects[index - 1].maxX, eight.meterRects[index].minX) }
    }

    func testBandwidthRowsFitInsideCanvasAndKeepMetersCentered() {
        let icon = StatusWidgetLayout(columnCount: 3, scale: 1, showBandwidth: false)
        let widget = StatusWidgetLayout(columnCount: 3, scale: 1, showBandwidth: true)
        XCTAssertGreaterThan(widget.size.width, icon.size.width)
        XCTAssertEqual(widget.meterRects, icon.meterRects)
        let upload = try! XCTUnwrap(widget.uploadRect)
        let download = try! XCTUnwrap(widget.downloadRect)
        let bounds = CGRect(origin: .zero, size: widget.size)
        XCTAssertTrue(bounds.contains(upload))
        XCTAssertTrue(bounds.contains(download))
        XCTAssertGreaterThanOrEqual(upload.minY, download.maxY)
        XCTAssertEqual((upload.midY + download.midY) / 2, widget.meterRects[0].midY, accuracy: 0.001)
    }

    func testRenderedWidgetIncludesAllEightMetersAndBandwidthInOneImage() {
        var settings = AppSettings()
        settings.columns = (0..<8).map { _ in ColumnConfiguration(metric: .cpu, colour: .mint) }
        settings.showBandwidth = true
        let sample = Snapshot(timestamp: 1, readings: [
            .cpu: MetricReading(value: 100, detail: "", timestamp: 1),
            .upload: MetricReading(value: 8_100, detail: "", timestamp: 1),
            .download: MetricReading(value: 8_800, detail: "", timestamp: 1)
        ])
        let layout = MeterImage.layout(settings: settings, snapshot: sample)
        let image = MeterImage.make(settings: settings, snapshot: sample, levels: Array(repeating: .normal, count: 8), appearance: NSAppearance(named: .aqua)!)
        XCTAssertEqual(image.size, layout.size)
        var rect = CGRect(origin: .zero, size: image.size)
        let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        XCTAssertNotNil(cg)
        if let directory = ProcessInfo.processInfo.environment["GLIMPSE_RENDER_ARTIFACTS"], cg != nil {
            let preview = NSImage(size: CGSize(width: image.size.width * 4 + 24, height: 112))
            preview.lockFocus()
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
            NSRect(origin: .zero, size: preview.size).fill()
            image.draw(in: NSRect(x: 12, y: 12, width: image.size.width * 4, height: 88))
            preview.unlockFocus()
            var previewBounds = NSRect(origin: .zero, size: preview.size)
            let rendered = try! XCTUnwrap(preview.cgImage(forProposedRect: &previewBounds, context: nil, hints: nil))
            let png = try! XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
            try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try! png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("widget.png"))
        }
    }

    func testShortBandwidthReadingsLeaveOnlyOneDigitOfTrailingBudget() {
        let readout = BandwidthReadout(upload: 2_100, download: 5_000, bits: false)
        let actual = max(readout.upload.size().width, readout.download.size().width)
        let digit = NSAttributedString(string: "9", attributes: BandwidthReadout.attributes).size().width
        XCTAssertGreaterThanOrEqual(readout.width, actual)
        XCTAssertLessThanOrEqual(readout.width - actual, digit + 2)
        XCTAssertLessThan(readout.width, 60)
        let wider = BandwidthReadout(upload: 999_000, download: 99_900_000, bits: false)
        XCTAssertGreaterThanOrEqual(wider.width, max(wider.upload.size().width, wider.download.size().width))
    }

    func testCombinedGaugeFillsIndependentlyFromCenterAndHandlesIdleOrMissingHalf() {
        let track = CGRect(x: 1, y: 3, width: 4, height: 16)
        let full = DuplexGaugeLayout(track: track, upload: 50, download: 100, ceiling: 100)
        let up = try! XCTUnwrap(full.upload)
        let down = try! XCTUnwrap(full.download)
        XCTAssertEqual(up.minY, 11.5)
        XCTAssertEqual(up.height, 3.75)
        XCTAssertEqual(down.maxY, 10.5)
        XCTAssertEqual(down.height, 7.5)
        XCTAssertEqual(down.minY, track.minY)

        let equal = DuplexGaugeLayout(track: track, upload: 100, download: 100, ceiling: 100)
        XCTAssertEqual(equal.upload?.height, 7.5)
        XCTAssertEqual(equal.download?.height, 7.5)
        let mixed = DuplexGaugeLayout(track: track, upload: nil, download: 0, ceiling: 100)
        XCTAssertNil(mixed.upload)
        XCTAssertEqual(mixed.download?.height, 0)
        let invalid = DuplexGaugeLayout(track: track, upload: .infinity, download: -1, ceiling: 100)
        XCTAssertNil(invalid.upload)
        XCTAssertNil(invalid.download)
    }

    func testDuplexGaugeRendersBothColoursWithCompactReadout() throws {
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .cpu, colour: .mint),
                            ColumnConfiguration(metric: .memory, colour: .purple),
                            ColumnConfiguration(metric: .download, colour: .mint, isCombinedNetwork: true, secondaryColour: .blue)]
        settings.networkCeiling = 10_000
        settings.showBandwidth = true
        let sample = Snapshot(timestamp: 1, readings: [
            .cpu: MetricReading(value: 35, detail: "", timestamp: 1),
            .memory: MetricReading(value: 70, detail: "", timestamp: 1),
            .upload: MetricReading(value: 5_000, detail: "", timestamp: 1),
            .download: MetricReading(value: 10_000, detail: "", timestamp: 1)
        ])
        let image = MeterImage.make(settings: settings, snapshot: sample, levels: [.normal, .normal, .normal], secondaryLevels: [nil, nil, .normal], appearance: NSAppearance(named: .aqua)!)
        XCTAssertLessThan(image.size.width, 90)
        var bounds = NSRect(origin: .zero, size: image.size)
        XCTAssertNotNil(image.cgImage(forProposedRect: &bounds, context: nil, hints: nil))
        if let directory = ProcessInfo.processInfo.environment["GLIMPSE_RENDER_ARTIFACTS"] {
            let preview = NSImage(size: CGSize(width: image.size.width * 5 + 24, height: 134))
            preview.lockFocus()
            NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
            NSRect(origin: .zero, size: preview.size).fill()
            image.draw(in: NSRect(x: 12, y: 12, width: image.size.width * 5, height: 110))
            preview.unlockFocus()
            var previewBounds = NSRect(origin: .zero, size: preview.size)
            let cg = try XCTUnwrap(preview.cgImage(forProposedRect: &previewBounds, context: nil, hints: nil))
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("duplex.png"))
        }
    }
}
