// Renders the DMG window background: usage `swift background.swift <out.png> <scale> <subtitle>`.
// Light gradient so Finder's dark icon labels stay readable.
import AppKit

let arguments = CommandLine.arguments
let output = URL(fileURLWithPath: arguments[1])
let scale = CGFloat(Double(arguments[2]) ?? 1)
let subtitle = arguments.count > 3 ? arguments[3] : ""
let size = CGSize(width: 660, height: 420)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSGradient(colors: [NSColor(srgbRed: 0.96, green: 0.95, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.84, green: 0.91, blue: 1.00, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -60)

func centered(_ text: String, y: CGFloat, size points: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: points, weight: weight),
        .foregroundColor: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.30, alpha: alpha)]
    let string = NSAttributedString(string: text, attributes: attributes)
    string.draw(at: NSPoint(x: (size.width - string.size().width) / 2, y: y))
}
// AppKit's origin is bottom-left; icons sit at y = 190 from the top (230 from the bottom).
centered("Glimpse", y: 360, size: 22, weight: .semibold, alpha: 0.9)
if !subtitle.isEmpty { centered(subtitle, y: 340, size: 12, weight: .regular, alpha: 0.6) }
// Kept high: recent Finder versions may show path/status bars over the bottom.
centered("Drag Glimpse to Applications to install", y: 120, size: 14, weight: .medium, alpha: 0.75)

// Arrow between the two icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 270, y: 230))
arrow.line(to: NSPoint(x: 380, y: 230))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
NSColor(srgbRed: 0.33, green: 0.40, blue: 0.70, alpha: 0.75).setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 366, y: 244))
head.line(to: NSPoint(x: 390, y: 230))
head.line(to: NSPoint(x: 366, y: 216))
head.lineWidth = 4
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: output)
