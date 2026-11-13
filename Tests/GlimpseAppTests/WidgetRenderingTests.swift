import XCTest
import AppKit
import GlimpseCore
@testable import GlimpseApp

final class WidgetRenderingTests: XCTestCase {
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
        let layout = StatusWidgetLayout(columnCount: 8, scale: 1, showBandwidth: true)
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
}
