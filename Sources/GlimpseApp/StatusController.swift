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
    private var thresholds: [UUID: ThresholdLatch] = [:]

    init(store: MonitoringStore, showSettings: @escaping () -> Void) {
        self.store = store
        super.init()
        statusItem.autosaveName = "GlimpseMain"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
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
        thresholds = thresholds.filter { id, _ in settings.columns.contains { $0.id == id } }
        let levels = settings.columns.map { column in
            var latch = thresholds[column.id] ?? ThresholdLatch()
            let result = latch.evaluate(value: store.snapshot.readings[column.metric]?.value, column: column,
                                       deadband: column.metric == .thermal ? 0 : (column.metric == .download || column.metric == .upload ? settings.networkCeiling * 0.01 : 1))
            thresholds[column.id] = latch
            return result
        }
        button.image = MeterImage.make(settings: settings, snapshot: store.snapshot, levels: levels, appearance: button.effectiveAppearance)
        button.title = ""
        statusItem.length = max(NSStatusItem.squareLength, (button.image?.size.width ?? 0) + 8)
        let summary = settings.columns.map { column in
            "\(column.metric.title): \(MetricPresentation.formatted(value: store.snapshot.readings[column.metric]?.value, metric: column.metric, bits: settings.bandwidthInBits))"
        }.joined(separator: ", ")
        button.toolTip = summary
        button.setAccessibilityLabel("Glimpse. \(summary). Show detailed status.")
    }
}
