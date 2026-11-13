import Foundation

/// One coordinate system for the meters and both text rows; NSButton never lays
/// out a multiline title independently from its image.
struct StatusWidgetLayout {
    let size: CGSize
    let meterRects: [CGRect]
    let uploadRect: CGRect?
    let downloadRect: CGRect?

    init(columnCount: Int, scale: Double, showBandwidth: Bool) {
        let count = min(8, max(1, columnCount))
        let factor = CGFloat(scale.isFinite ? min(1.5, max(0.75, scale)) : 1)
        let width = 4 * factor
        let gap = 2 * factor
        let metersWidth = CGFloat(count) * width + CGFloat(count - 1) * gap + 2
        meterRects = (0..<count).map { CGRect(x: 1 + CGFloat($0) * (width + gap), y: 3, width: width, height: 16) }
        if showBandwidth {
            let x = metersWidth + 7
            uploadRect = CGRect(x: x, y: 11, width: 80, height: 11)
            downloadRect = CGRect(x: x, y: 0, width: 80, height: 11)
            size = CGSize(width: x + 80, height: 22)
        } else {
            uploadRect = nil
            downloadRect = nil
            size = CGSize(width: metersWidth, height: 22)
        }
    }
}
