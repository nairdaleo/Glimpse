import AppKit
import GlimpseCore

extension MeterColour {
    var nsColor: NSColor {
        switch self {
        case .mint: return .systemTeal
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .orange: return .systemOrange
        case .pink: return .systemPink
        }
    }
}

enum MeterImage {
    static func make(settings: AppSettings, snapshot: Snapshot, levels: [ThresholdLevel?], appearance: NSAppearance) -> NSImage {
        let layout = StatusWidgetLayout(columnCount: settings.columns.count, scale: settings.columnScale, showBandwidth: settings.showBandwidth)
        var result = NSImage(size: layout.size)
        appearance.performAsCurrentDrawingAppearance {
            result = NSImage(size: layout.size, flipped: false) { _ in
              appearance.performAsCurrentDrawingAppearance {
                for (index, column) in settings.columns.prefix(layout.meterRects.count).enumerated() {
                    let track = layout.meterRects[index]
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
                    let raw = snapshot.readings[column.metric]?.value
                    guard let amount = MetricPresentation.normalized(value: raw, metric: column.metric, networkCeiling: settings.networkCeiling) else {
                        NSColor.secondaryLabelColor.setStroke()
                        let slash = NSBezierPath()
                        slash.move(to: NSPoint(x: track.minX + 0.5, y: track.midY - 1.5))
                        slash.line(to: NSPoint(x: track.maxX - 0.5, y: track.midY + 1.5))
                        slash.lineWidth = 1
                        slash.stroke()
                        continue
                    }
                    let height = max(1, CGFloat(amount) * track.height)
                    var colour = settings.monochrome ? NSColor.labelColor : column.colour.nsColor
                    if !settings.monochrome, index < levels.count {
                        if levels[index] == .critical { colour = .systemRed }
                        else if levels[index] == .warning { colour = .systemYellow }
                    }
                    colour.setFill()
                    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width, height: height), xRadius: 1.2, yRadius: 1.2).fill()
                }
                let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                for (metric, row, arrow) in [(MetricID.upload, layout.uploadRect, "↑"), (.download, layout.downloadRect, "↓")] {
                    guard let row = row else { continue }
                    let value = MetricPresentation.formatted(value: snapshot.readings[metric]?.value, metric: metric, bits: settings.bandwidthInBits)
                    let text = NSAttributedString(string: "\(arrow) \(value)", attributes: attributes)
                    // Center each line's actual measured bounds in its allocated half.
                    let y = row.midY - text.size().height / 2
                    text.draw(at: CGPoint(x: row.minX, y: y))
                }
              }
                return true
            }
        }
        result.isTemplate = false
        return result
    }
}
