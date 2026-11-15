import AppKit
import SwiftUI
import GlimpseCore
import GlimpseMonitor

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: MonitoringStore!
    private var statusController: StatusController!
    private var settingsWindow: NSWindow?
    private var services: LifecycleServices!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = MonitoringStore()
        services = LifecycleServices()
        statusController = StatusController(store: store, showSettings: { [weak self] metric in self?.showSettings(panel: metric) })
        #if APP_STORE
        _ = TipJar.shared // starts the StoreKit transaction listener
        #endif
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { store?.stop() }

    func applicationDidBecomeActive(_ notification: Notification) { services?.refreshLoginStatus() }

    private func showSettings(panel: UUID? = nil) {
        services.refreshLoginStatus()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 610), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = String(localized: "Glimpse Settings")
            window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(store: store, services: services))
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 590)
            window.center()
            settingsWindow = window
        }
        if let panel = panel {
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(store: store, services: services, requestedPanel: panel))
        }
        NSApp.activate(ignoringOtherApps: true)
        store.setSettingsVisible(true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        #if APP_STORE
        ReviewPrompt.requestIfDue()
        #endif
    }

    func windowWillClose(_ notification: Notification) {
        store.setSettingsVisible(false)
        // A closed window's hosting view keeps re-rendering every sample; showSettings rebuilds it.
        DispatchQueue.main.async { self.settingsWindow = nil }
    }
    func windowDidBecomeKey(_ notification: Notification) { services?.refreshLoginStatus() }
}

@main
enum GlimpseMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-cards"), CommandLine.arguments.indices.contains(index + 1) {
            CardRenderer.run(directory: CommandLine.arguments[index + 1])
        } else if CommandLine.arguments.contains("--diagnose") {
            // A terminal-only native-reader check; never exports settings or personal paths.
            let sampler = NativeSampler()
            _ = sampler.sample(settings: AppSettings(), detailVisible: true)
            Thread.sleep(forTimeInterval: 1.1)
            let sample = sampler.sample(settings: AppSettings(), detailVisible: true)
            print("Glimpse native-reader diagnostic")
            print("Interface: \(sample.networkInterface)")
            for metric in MetricID.allCases {
                let reading = sample.readings[metric]
                print("\(metric.title): \(MetricPresentation.formatted(value: reading?.value, metric: metric)) — \(reading?.detail ?? "Unavailable")")
            }
        } else {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
