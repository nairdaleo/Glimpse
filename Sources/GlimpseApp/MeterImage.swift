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
    static func layout(settings: AppSettings, snapshot: Snapshot) -> StatusWidgetLayout {
        let labels = BandwidthReadout(upload: snapshot.readings[.upload]?.value, download: snapshot.readings[.download]?.value, bits: settings.bandwidthInBits)
        return StatusWidgetLayout(columnCount: settings.columns.count, scale: settings.columnScale, showBandwidth: settings.showBandwidth, bandwidthWidth: labels.width)
    }

    static func make(settings: AppSettings, snapshot: Snapshot, levels: [ThresholdLevel?], secondaryLevels: [ThresholdLevel?] = [], appearance: NSAppearance) -> NSImage {
        let labels = BandwidthReadout(upload: snapshot.readings[.upload]?.value, download: snapshot.readings[.download]?.value, bits: settings.bandwidthInBits)
        let layout = StatusWidgetLayout(columnCount: settings.columns.count, scale: settings.columnScale, showBandwidth: settings.showBandwidth, bandwidthWidth: labels.width)
        var result = NSImage(size: layout.size)
        appearance.performAsCurrentDrawingAppearance {
            result = NSImage(size: layout.size, flipped: false) { _ in
              appearance.performAsCurrentDrawingAppearance {
                for (index, column) in settings.columns.prefix(layout.meterRects.count).enumerated() {
                    let track = layout.meterRects[index]
                    NSColor.labelColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
                    func colour(_ base: MeterColour, level: ThresholdLevel?) -> NSColor {
                        if settings.monochrome { return .labelColor }
                        if level == .critical { return .systemRed }
                        if level == .warning { return .systemYellow }
                        return base.nsColor
                    }
                    if column.isCombinedNetwork {
                        let halves = DuplexGaugeLayout(track: track, upload: snapshot.readings[.upload]?.value,
                                                       download: snapshot.readings[.download]?.value, ceiling: settings.networkCeiling)
                        let upColour = colour(column.colour, level: index < levels.count ? levels[index] : nil)
                        let downColour = colour(column.secondaryColour, level: index < secondaryLevels.count ? secondaryLevels[index] : nil)
                        for (rect, fill, upper) in [(halves.upload, upColour, true), (halves.download, downColour, false)] {
                            if let rect = rect {
                                if rect.height > 0 { fill.setFill(); NSBezierPath(rect: rect).fill() }
                            } else {
                                // Missing half only: do not hide the other direction's reading.
                                NSColor.secondaryLabelColor.setStroke()
                                let slash = NSBezierPath()
                                let y = track.midY + (upper ? 4 : -4)
                                slash.move(to: CGPoint(x: track.minX + 0.5, y: y - 1))
                                slash.line(to: CGPoint(x: track.maxX - 0.5, y: y + 1))
                                slash.lineWidth = 1
                                slash.stroke()
                            }
                        }
                        NSColor.labelColor.withAlphaComponent(0.55).setStroke()
                        let center = NSBezierPath()
                        center.move(to: CGPoint(x: track.minX, y: track.midY))
                        center.line(to: CGPoint(x: track.maxX, y: track.midY))
                        center.lineWidth = 0.5
                        center.stroke()
                        continue
                    }
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
                    colour(column.colour, level: index < levels.count ? levels[index] : nil).setFill()
                    NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: track.width, height: height), xRadius: 1.2, yRadius: 1.2).fill()
                }
                for (text, row) in [(labels.upload, layout.uploadRect), (labels.download, layout.downloadRect)] {
                    guard let row = row else { continue }
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
