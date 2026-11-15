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
    private let showSettings: (UUID?) -> Void
    private var maximumPanelSize = CGSize(width: 1400, height: 850)
    private var renderedAppearance: NSAppearance.Name?
    private var displaysAsleep = false
    /// Uptime when the popover closed with the pointer on the menu-bar icon.
    private var closedOverIcon: TimeInterval?
    private var closingFromToggle = false
    private var shortcut: GlobalShortcut?
    /// Meter states in the image currently shown; nil forces the next redraw.
    private var shownMeters: [MeterState]?

    init(store: MonitoringStore, showSettings: @escaping (UUID?) -> Void) {
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
        store.$snapshot.combineLatest(store.$settings).sink { [weak self] _, _ in
            // @Published emits before assignment; render after both values settle.
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        appearanceObserver = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            // Setting the image re-announces effectiveAppearance; only a real light/dark change needs a redraw.
            DispatchQueue.main.async {
                guard let self, self.statusItem.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != self.renderedAppearance else { return }
                self.render()
            }
        }
        store.$settings.sink { [weak self] _ in self?.shownMeters = nil }.store(in: &subscriptions)
        shortcut = GlobalShortcut { [weak self] in self?.togglePanel() }
        store.$settings.map(\.panelShortcut).removeDuplicates().sink { [weak self] value in
            guard let self else { return }
            self.store.shortcutUnavailable = !(self.shortcut?.update(value) ?? true)
        }.store(in: &subscriptions)
        // Nobody can see the icon while the displays sleep; sampling and history continue.
        let workspace = NSWorkspace.shared.notificationCenter
        displaysAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification).sink { [weak self] _ in self?.displaysAsleep = true }.store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification).sink { [weak self] _ in
            self?.displaysAsleep = false
            self?.render()
        }.store(in: &subscriptions)
        render()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closingFromToggle = true
            popover.performClose(nil)
            closingFromToggle = false
            return
        }
        // Clicking the icon closes the transient popover 15-40 ms before this action
        // runs (sometimes after the button is already released). A close that
        // recent, with the pointer on the icon, was this click: don't reopen.
        if let closedAt = closedOverIcon {
            closedOverIcon = nil
            if ProcessInfo.processInfo.systemUptime - closedAt < 0.3 { return }
        }
        store.setDetailVisible(true)
        updatePanelHost()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverWillClose(_ notification: Notification) {
        // A transient popover closes when the menu-bar icon is clicked, just before
        // the button's action runs. Remember a close with the pointer on the icon.
        guard !closingFromToggle, let button = statusItem.button, let window = button.window else { return }
        let iconOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        if iconOnScreen.contains(NSEvent.mouseLocation) {
            closedOverIcon = ProcessInfo.processInfo.systemUptime
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.setDetailVisible(false)
        // A hidden hosting view keeps diffing every sample; togglePanel rebuilds it on open.
        popover.contentViewController = nil
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

    private func openSettings(_ metric: UUID?) {
        popover.performClose(nil)
        showSettings(metric)
    }

    private func render() {
        guard !displaysAsleep, let button = statusItem.button else { return }
        let settings = store.settings
        thresholds = thresholds.filter { id, _ in settings.columns.contains { $0.id == id } }
        downloadThresholds = downloadThresholds.filter { id, _ in settings.columns.contains { $0.id == id && $0.isCombinedNetwork } }
        let levels = settings.columns.map { column in
            var latch = thresholds[column.id] ?? ThresholdLatch()
            let result = latch.evaluate(value: store.snapshot.displayReading(for: column.isCombinedNetwork ? .upload : column.metric, interface: column.networkInterface)?.value, column: column,
                                       deadband: column.metric == .thermal ? 0 : (column.metric == .download || column.metric == .upload ? settings.networkCeiling(for: column.isCombinedNetwork ? .upload : column.metric) * 0.01 : 1))
            thresholds[column.id] = latch
            return result
        }
        let secondaryLevels: [ThresholdLevel?] = settings.columns.map { column in
            guard column.isCombinedNetwork else { return nil }
            var latch = downloadThresholds[column.id] ?? ThresholdLatch()
            let result = latch.evaluate(value: store.snapshot.displayReading(for: .download, interface: column.networkInterface)?.value, column: column.downloadThresholdColumn, deadband: settings.networkCeiling * 0.01)
            downloadThresholds[column.id] = latch
            return result
        }
        var meters: [MeterState] = []
        for (index, column) in settings.columns.enumerated() {
            for (metric, level) in column.isCombinedNetwork ? [(MetricID.upload, levels[index]), (.download, secondaryLevels[index])] : [(column.metric, levels[index])] {
                let value = store.snapshot.displayReading(for: metric, interface: column.networkInterface)?.value
                meters.append(MeterState(fill: MetricPresentation.normalized(value: value, metric: metric, networkCeiling: settings.networkCeiling(for: metric)), level: level))
            }
        }
        let appearance = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        // The bandwidth readout shows exact numbers, so it redraws every sample.
        if appearance != renderedAppearance || settings.showBandwidth || IconRefresh.needsRedraw(shown: shownMeters, next: meters) || button.image == nil {
            shownMeters = meters
            renderedAppearance = appearance
            button.image = MeterImage.make(settings: settings, snapshot: store.snapshot, levels: levels, secondaryLevels: secondaryLevels, appearance: button.effectiveAppearance)
        }
        if !button.title.isEmpty { button.title = "" }
        let length = max(NSStatusItem.squareLength, (button.image?.size.width ?? 0) + 8)
        if statusItem.length != length { statusItem.length = length }
        if popover.isShown {
            popover.contentSize = StatusPanelLayout(settings: settings, maximumSize: maximumPanelSize).size
            popover.positioningRect = button.bounds
        }
        let summary = settings.columns.map { column in
            if column.isCombinedNetwork {
                let up = MetricPresentation.formatted(value: store.snapshot.displayReading(for: .upload, interface: column.networkInterface)?.value, metric: .upload, bits: settings.bandwidthInBits, units: settings.bandwidthUnits)
                let down = MetricPresentation.formatted(value: store.snapshot.displayReading(for: .download, interface: column.networkInterface)?.value, metric: .download, bits: settings.bandwidthInBits, units: settings.bandwidthUnits)
                return "\(column.networkInterface ?? "Auto"): Upload \(up), Download \(down)"
            }
            return "\(column.displayTitle)\(column.isNetwork ? " (" + (column.networkInterface ?? "Auto") + ")" : ""): \(MetricPresentation.formatted(value: store.snapshot.displayReading(for: column.metric, interface: column.networkInterface)?.value, metric: column.metric, bits: settings.bandwidthInBits, units: settings.bandwidthUnits))"
        }.joined(separator: ", ")
        button.toolTip = summary
        button.setAccessibilityLabel("Glimpse. \(summary). Show detailed status.")
    }
}
