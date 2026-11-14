import Foundation
import GlimpseCore

/// One coordinate system for the meters and both text rows; NSButton never lays
/// out a multiline title independently from its image.
struct StatusWidgetLayout {
    let size: CGSize
    let meterRects: [CGRect]
    let uploadRect: CGRect?
    let downloadRect: CGRect?

    init(columnCount: Int, scale: Double, showBandwidth: Bool, bandwidthWidth: CGFloat = 50) {
        let count = min(8, max(1, columnCount))
        let factor = CGFloat(scale.isFinite ? min(1.5, max(0.75, scale)) : 1)
        let width = 4 * factor
        let gap = 2 * factor
        let metersWidth = CGFloat(count) * width + CGFloat(count - 1) * gap + 2
        meterRects = (0..<count).map { CGRect(x: 1 + CGFloat($0) * (width + gap), y: 3, width: width, height: 16) }
        if showBandwidth {
            let x = metersWidth + 7
            let textWidth = max(1, bandwidthWidth.isFinite ? bandwidthWidth : 50)
            uploadRect = CGRect(x: x, y: 11, width: textWidth, height: 11)
            downloadRect = CGRect(x: x, y: 0, width: textWidth, height: 11)
            size = CGSize(width: x + textWidth, height: 22)
        } else {
            uploadRect = nil
            downloadRect = nil
            size = CGSize(width: metersWidth, height: 22)
        }
    }
}

struct DuplexGaugeLayout {
    let upload: CGRect?
    let download: CGRect?

    init(track: CGRect, upload: Double?, download: Double?, ceiling: Double) {
        let half = max(0, (track.height - 1) / 2)
        func amount(_ value: Double?, metric: MetricID) -> CGFloat? {
            guard let value = value, value >= 0,
                  let normalized = MetricPresentation.normalized(value: value, metric: metric, networkCeiling: ceiling) else { return nil }
            return CGFloat(normalized) * half
        }
        self.upload = amount(upload, metric: .upload).map { CGRect(x: track.minX, y: track.midY + 0.5, width: track.width, height: $0) }
        self.download = amount(download, metric: .download).map { CGRect(x: track.minX, y: track.midY - 0.5 - $0, width: track.width, height: $0) }
    }
}
