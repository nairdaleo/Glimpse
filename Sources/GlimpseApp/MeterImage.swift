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
        var result = NSImage(size: NSSize(width: 18, height: 18))
        appearance.performAsCurrentDrawingAppearance {
            result = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                for (index, column) in settings.columns.prefix(3).enumerated() {
                    let x = CGFloat(index * 6 + 1)
                    let track = NSRect(x: x, y: 1, width: 4, height: 16)
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
                    let raw = snapshot.readings[column.metric]?.value
                    guard let amount = MetricPresentation.normalized(value: raw, metric: column.metric, networkCeiling: settings.networkCeiling) else {
                        NSColor.secondaryLabelColor.setStroke()
                        let slash = NSBezierPath()
                        slash.move(to: NSPoint(x: x + 0.5, y: 7))
                        slash.line(to: NSPoint(x: x + 3.5, y: 10))
                        slash.lineWidth = 1
                        slash.stroke()
                        continue
                    }
                    let height = max(1, CGFloat(amount) * 16)
                    var colour = settings.monochrome ? NSColor.labelColor : column.colour.nsColor
                    if !settings.monochrome, index < levels.count {
                        if levels[index] == .critical { colour = .systemRed }
                        else if levels[index] == .warning { colour = .systemYellow }
                    }
                    colour.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: 4, height: height), xRadius: 1.2, yRadius: 1.2).fill()
                }
                return true
            }
        }
        result.isTemplate = false
        return result
    }
}
