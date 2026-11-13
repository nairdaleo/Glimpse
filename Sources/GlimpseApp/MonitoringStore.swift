import AppKit
import Combine
import GlimpseCore
import GlimpseMonitor

@MainActor
final class MonitoringStore: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var snapshot = Snapshot(timestamp: ProcessInfo.processInfo.systemUptime)
    @Published private(set) var history = MetricHistory()
    @Published private(set) var detailVisible = false

    private let worker = SamplingWorker()
    private let defaults: UserDefaults
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var sleeping = false
    private var settingsVisible = false
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private static let settingsKey = "glimpse.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded.validated()
        } else {
            settings = AppSettings()
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        })
        schedule()
    }

    func change(_ edit: (inout AppSettings) -> Void) {
        var updated = settings
        edit(&updated)
        settings = updated.validated()
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        schedule()
    }

    func resetSettings() {
        change { $0 = AppSettings() }
    }

    func setDetailVisible(_ visible: Bool) {
        guard detailVisible != visible else { return }
        detailVisible = visible
        schedule()
    }

    func setSettingsVisible(_ visible: Bool) {
        guard settingsVisible != visible else { return }
        settingsVisible = visible
        schedule()
    }

    func stop() {
        generation += 1
        timer?.cancel()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        workspaceObservers.removeAll()
    }

    private func sleep() {
        sleeping = true
        generation += 1
        timer?.cancel()
        timer = nil
        worker.reset()
    }

    private func wake() {
        sleeping = false
        schedule()
    }

    private func schedule() {
        generation += 1
        timer?.cancel()
        timer = nil
        guard !sleeping else { return }
        let version = generation
        let configuration = settings
        let visible = detailVisible
        let configuring = settingsVisible
        let interval = max(configuration.refreshInterval, ProcessInfo.processInfo.isLowPowerModeEnabled ? 5 : 1)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        source.setEventHandler { [weak self, worker] in
            worker.sample(settings: configuration, detailVisible: visible, configurationVisible: configuring) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.generation == version else { return }
                    self.snapshot = result
                    self.history.append(result)
                }
            }
        }
        timer = source
        source.resume()
    }
}

/// The only unchecked boundary: mutable NativeSampler never leaves this private
/// serial queue. Every public operation enqueues work; only value snapshots escape.
private final class SamplingWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.tastyjam.glimpse.sampling", qos: .utility)
    private let sampler = NativeSampler()

    func sample(settings: AppSettings, detailVisible: Bool, configurationVisible: Bool, completion: @escaping @Sendable (Snapshot) -> Void) {
        queue.async { [self] in completion(sampler.sample(settings: settings, detailVisible: detailVisible, configurationVisible: configurationVisible)) }
    }

    func reset() { queue.async { [self] in sampler.resetBaselines() } }
}
