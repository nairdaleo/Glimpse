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
    private var downloadThresholds: [UUID: ThresholdLatch] = [:]
    private let showSettings: (MetricID?) -> Void
    private var maximumPanelSize = CGSize(width: 1400, height: 850)

    init(store: MonitoringStore, showSettings: @escaping (MetricID?) -> Void) {
        self.store = store
        self.showSettings = showSettings
        super.init()
        statusItem.autosaveName = "GlimpseMain"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        updatePanelHost()
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
            updatePanelHost()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.setDetailVisible(false)
    }

    private func updatePanelHost() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        if let screen = screen {
            maximumPanelSize = CGSize(width: max(210, screen.visibleFrame.width - 24), height: max(190, screen.visibleFrame.height - 48))
        }
        popover.contentViewController = NSHostingController(rootView: StatusPanel(store: store, showSettings: { [weak self] in
            self?.openSettings(nil)
        }, editCard: { [weak self] metric in
            self?.openSettings(metric)
        }, maximumSize: maximumPanelSize))
        popover.contentSize = StatusPanelLayout(settings: store.settings, maximumSize: maximumPanelSize).size
    }

    private func openSettings(_ metric: MetricID?) {
        popover.performClose(nil)
        showSettings(metric)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let settings = store.settings
        thresholds = thresholds.filter { id, _ in settings.columns.contains { $0.id == id } }
        downloadThresholds = downloadThresholds.filter { id, _ in settings.columns.contains { $0.id == id && $0.isCombinedNetwork } }
        let levels = settings.columns.map { column in
            var latch = thresholds[column.id] ?? ThresholdLatch()
            let result = latch.evaluate(value: store.snapshot.readings[column.isCombinedNetwork ? .upload : column.metric]?.value, column: column,
                                       deadband: column.metric == .thermal ? 0 : (column.metric == .download || column.metric == .upload ? settings.networkCeiling * 0.01 : 1))
            thresholds[column.id] = latch
            return result
        }
        let secondaryLevels: [ThresholdLevel?] = settings.columns.map { column in
            guard column.isCombinedNetwork else { return nil }
            var latch = downloadThresholds[column.id] ?? ThresholdLatch()
            let result = latch.evaluate(value: store.snapshot.readings[.download]?.value, column: column, deadband: settings.networkCeiling * 0.01)
            downloadThresholds[column.id] = latch
            return result
        }
        button.image = MeterImage.make(settings: settings, snapshot: store.snapshot, levels: levels, secondaryLevels: secondaryLevels, appearance: button.effectiveAppearance)
        button.title = ""
        statusItem.length = max(NSStatusItem.squareLength, (button.image?.size.width ?? 0) + 8)
        if popover.isShown {
            popover.contentSize = StatusPanelLayout(settings: settings, maximumSize: maximumPanelSize).size
            popover.positioningRect = button.bounds
        }
        let summary = settings.columns.map { column in
            if column.isCombinedNetwork {
                let up = MetricPresentation.formatted(value: store.snapshot.readings[.upload]?.value, metric: .upload, bits: settings.bandwidthInBits)
                let down = MetricPresentation.formatted(value: store.snapshot.readings[.download]?.value, metric: .download, bits: settings.bandwidthInBits)
                return "Upload: \(up), Download: \(down)"
            }
            return "\(column.displayTitle): \(MetricPresentation.formatted(value: store.snapshot.readings[column.metric]?.value, metric: column.metric, bits: settings.bandwidthInBits))"
        }.joined(separator: ", ")
        button.toolTip = summary
        button.setAccessibilityLabel("Glimpse. \(summary). Show detailed status.")
    }
}
