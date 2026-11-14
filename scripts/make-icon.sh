#!/bin/bash
# Renders packaging/icon/Glimpse.svg into an .icns (default build/Glimpse.icns).
#   scripts/make-icon.sh [output.icns]
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build/Glimpse.icns}"
iconset="$(mktemp -d)/Glimpse.iconset"
mkdir -p "$iconset" "$(dirname "$out")"
swift - "$PWD/packaging/icon/Glimpse.svg" "$iconset" <<'SWIFT'
import AppKit
let args = CommandLine.arguments
guard let svg = NSImage(contentsOfFile: args[1]) else { fatalError("cannot read \(args[1])") }
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]).appendingPathComponent(name))
    }
}
SWIFT
iconutil -c icns "$iconset" -o "$out"
rm -rf "$(dirname "$iconset")"
echo "$out"
