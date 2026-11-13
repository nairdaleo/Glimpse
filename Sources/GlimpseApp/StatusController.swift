import AppKit
import Combine
import SwiftUI
import GlimpseCore

@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let store: MonitoringStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObserver: NSKeyValueObservation?
    private var thresholds = Array(repeating: ThresholdLatch(), count: 3)

    init(store: MonitoringStore, showSettings: @escaping () -> Void) {
        self.store = store
        super.init()
        statusItem.autosaveName = "GlimpseMain"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: StatusPanel(store: store, showSettings: { [weak self] in
            self?.popover.performClose(nil)
            showSettings()
        }))
        store.$snapshot.combineLatest(store.$settings).sink { [weak self] _, _ in
            // @Published emits before assignment; render after both values settle.
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        appearanceObserver = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.render() }
        }
        render()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.setDetailVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.setDetailVisible(false)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let settings = store.settings
        let levels = settings.columns.enumerated().map { index, column in
            thresholds[index].evaluate(value: store.snapshot.readings[column.metric]?.value, column: column,
                                       deadband: column.metric == .thermal ? 0 : (column.metric == .download || column.metric == .upload ? settings.networkCeiling * 0.01 : 1))
        }
        button.image = MeterImage.make(settings: settings, snapshot: store.snapshot, levels: levels, appearance: button.effectiveAppearance)
        if settings.showBandwidth {
            statusItem.length = 112
            let up = MetricPresentation.formatted(value: store.snapshot.readings[.upload]?.value, metric: .upload, bits: settings.bandwidthInBits)
            let down = MetricPresentation.formatted(value: store.snapshot.readings[.download]?.value, metric: .download, bits: settings.bandwidthInBits)
            let title = NSMutableAttributedString(string: "  ↑ \(up)\n  ↓ \(down)")
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            title.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: NSRange(location: 0, length: title.length))
            button.attributedTitle = title
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
        }
        let summary = settings.columns.map { column in
            "\(column.metric.title): \(MetricPresentation.formatted(value: store.snapshot.readings[column.metric]?.value, metric: column.metric, bits: settings.bandwidthInBits))"
        }.joined(separator: ", ")
        button.toolTip = summary
        button.setAccessibilityLabel("Glimpse. \(summary). Show detailed status.")
    }
}
