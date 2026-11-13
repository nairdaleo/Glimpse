import AppKit

/// Monterey's login item launches the containing app, then always exits.
@main
enum GlimpseLoginHelper {
    @MainActor static func main() {
        let parentURL = (0..<4).reduce(Bundle.main.bundleURL) { url, _ in url.deletingLastPathComponent() }
        guard let parentBundle = Bundle(url: parentURL),
              parentBundle.bundleIdentifier == "com.tastyjam.glimpse" else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.tastyjam.glimpse").isEmpty else { return }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: parentURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { app.terminate(nil) }
        }
        // A failed Launch Services callback must not leave a resident login helper.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { app.terminate(nil) }
        app.run()
    }
}
