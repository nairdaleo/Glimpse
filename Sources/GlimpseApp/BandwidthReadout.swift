import AppKit
import GlimpseCore

struct BandwidthReadout {
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
        .foregroundColor: NSColor.labelColor
    ]
    let upload: NSAttributedString
    let download: NSAttributedString
    let width: CGFloat

    init(upload: Double?, download: Double?, bits: Bool) {
        let up = MetricPresentation.formatted(value: upload, metric: .upload, bits: bits)
        let down = MetricPresentation.formatted(value: download, metric: .download, bits: bits)
        self.upload = NSAttributedString(string: "↑ \(up)", attributes: Self.attributes)
        self.download = NSAttributedString(string: "↓ \(down)", attributes: Self.attributes)
        func budget(_ value: String, arrow: String) -> CGFloat {
            let unit = value.split(separator: " ").last.map(String.init)
            let knownUnit: String
            if let unit = unit, unit.hasSuffix("/s") { knownUnit = unit }
            else { knownUnit = bits ? "b/s" : "B/s" }
            return NSAttributedString(string: "\(arrow) 99.9 \(knownUnit)", attributes: Self.attributes).size().width
        }
        // Four numeric characters cover both 999 and 99.9. Reserve only the
        // current units, and expand for any longer formatter output.
        width = ceil(max(max(self.upload.size().width, self.download.size().width),
                         max(budget(up, arrow: "↑"), budget(down, arrow: "↓"))))
    }
}
