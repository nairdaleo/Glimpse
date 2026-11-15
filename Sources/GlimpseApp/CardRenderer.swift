import AppKit
import SwiftUI
import GlimpseCore
import GlimpseMonitor

/// `--render-cards <dir>`: samples live readings for a few seconds, then writes
/// PNGs of every saved panel at every card size, light and dark, for a visual
/// audit with real data. Local files only; nothing leaves the Mac.
enum CardRenderer {
    @MainActor static func run(directory: String) {
        _ = NSApplication.shared
        let settings = MonitoringStore.savedSettings()
        let sampler = NativeSampler()
        var history = MetricHistory()
        var networkHistory = NetworkHistory()
        var snapshot = sampler.sample(settings: settings, detailVisible: true).screenshotSafeIfRequested
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 1.05)
            snapshot = sampler.sample(settings: settings, detailVisible: true).screenshotSafeIfRequested
            history.append(snapshot)
            networkHistory.append(snapshot)
        }
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let sizes: [(String, PanelCardSize, PanelLargeOrientation, CGFloat, CGFloat)] = [
            ("compact", .compact, .vertical, 1, 70), ("regular", .regular, .vertical, 1, 150),
            ("large-vertical", .large, .vertical, 1, 310), ("large-horizontal", .large, .horizontal, 2, 150)]
        let width = settings.panelCardWidth
        var count = 0
        for (index, saved) in settings.panels.enumerated() {
            for (name, size, orientation, columns, height) in sizes {
                var panel = saved
                panel.appearance.size = size
                panel.appearance.largeOrientation = orientation
                let cardWidth = columns * width + (columns - 1) * StatusPanelLayout.spacing
                for (scheme, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let view = NSHostingView(rootView: MetricCardContent(panel: panel, snapshot: snapshot, history: history,
                                                                         networkHistory: networkHistory, settings: settings,
                                                                         width: cardWidth, height: height)
                        .padding(8).background(Color(NSColor.windowBackgroundColor)))
                    view.appearance = NSAppearance(named: appearanceName)
                    view.frame = NSRect(x: 0, y: 0, width: cardWidth + 16, height: height + 16)
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let file = String(format: "%02d-%@-%@-%@.png", index, panel.displayTitle.replacingOccurrences(of: " / ", with: "-"), name, scheme)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(file))
                    count += 1
                }
            }
        }
        print("Rendered \(count) cards from \(settings.panels.count) saved panels to \(url.path)")
    }
}

private extension Snapshot {
    var screenshotSafeIfRequested: Snapshot { ScreenshotMode.isOn ? screenshotSafe : self }
}
