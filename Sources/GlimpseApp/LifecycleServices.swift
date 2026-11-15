import AppKit
import Combine
import ServiceManagement
#if !APP_STORE
import Sparkle
#endif

/// Owns the operating-system login item and Sparkle's persistent update preferences.
@MainActor
final class LifecycleServices: ObservableObject {
    @Published private(set) var loginEnabled = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var updateConfigured = false
    @Published private(set) var updateStatus = String(localized: "Updates are not configured for this build.")
    @Published private(set) var loginStatus = ""

    private static let helperIdentifier = "com.tastyjam.glimpse.loginhelper"
    private static let legacyLoginRequestKey = "GlimpseLegacyLoginRequested"
#if !APP_STORE
    private var updaterController: SPUStandardUpdaterController?
#endif
    private var observations = Set<AnyCancellable>()

    init() {
        refreshLoginStatus()
        configureUpdater()
    }

    /// Uninstall: turn off Start at login, optionally forget settings, move
    /// this app bundle to the Trash (restorable), then quit.
    func removeApp(deletingSettings: Bool) {
        setLoginEnabled(false)
        if deletingSettings, let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Glimpse could not be moved to the Trash")
                    alert.informativeText = error.localizedDescription + " Quit Glimpse and drag it to the Trash instead."
                    alert.runModal()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    if service.status != .enabled && service.status != .requiresApproval { try service.register() }
                } else if service.status != .notRegistered {
                    try service.unregister()
                }
                refreshLoginStatus()
            } catch {
                refreshLoginStatus()
                loginStatus += " Could not change the login item: \(error.localizedDescription)"
            }
        } else {
            let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LoginItems/GlimpseLoginHelper.app")
            guard Bundle(url: helperURL)?.bundleIdentifier == Self.helperIdentifier else {
                refreshLoginStatus()
                loginStatus = String(localized: "The login helper is missing from this build.")
                return
            }
            // Monterey has no supported query for the actual state of this legacy item.
            guard SMLoginItemSetEnabled(Self.helperIdentifier as CFString, enabled) else {
                refreshLoginStatus()
                loginStatus += " macOS rejected the change."
                return
            }
            UserDefaults.standard.set(enabled, forKey: Self.legacyLoginRequestKey)
            refreshLoginStatus()
        }
    }

    func refreshLoginStatus() {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                loginEnabled = true
                loginStatus = String(localized: "Glimpse will start when you log in.")
            case .requiresApproval:
                loginEnabled = false
                loginStatus = String(localized: "Approval required. Enable Glimpse in System Settings > General > Login Items.")
            case .notRegistered:
                loginEnabled = false
                loginStatus = String(localized: "Start at login is off.")
            case .notFound:
                loginEnabled = false
                loginStatus = "macOS could not find this app's login item. Keep Glimpse in Applications and try again."
            @unknown default:
                loginEnabled = false
                loginStatus = "macOS reported an unknown login-item state."
            }
        } else {
            let request = UserDefaults.standard.object(forKey: Self.legacyLoginRequestKey) as? Bool
            loginEnabled = request ?? false
            let saved = request.map { $0 ? String(localized: "Last successful request: on.") : String(localized: "Last successful request: off.") }
                ?? String(localized: "No start-at-login request saved.")
            loginStatus = "\(saved) macOS 12 does not report the actual login-item state; verify by logging out and back in."
        }
    }

#if APP_STORE
    // Mac App Store edition: the store delivers updates and Sparkle is not linked.
    func setAutomaticChecks(_ enabled: Bool) {}
    func setAutomaticDownloads(_ enabled: Bool) {}
    func checkForUpdates() {}
    private func configureUpdater() { updateStatus = String(localized: "Updates are delivered by the App Store.") }
#else
    func setAutomaticChecks(_ enabled: Bool) {
        guard updateConfigured, let updater = updaterController?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        refreshUpdateState()
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard updateConfigured, let updater = updaterController?.updater else { return }
        guard !enabled || updater.allowsAutomaticUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
        refreshUpdateState()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController?.checkForUpdates(nil)
        refreshUpdateState()
    }

    private func configureUpdater() {
        // Configuration comes from release metadata, never an inferred or placeholder feed.
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }

        // Info.plist supplies the defaults; registration also protects unbundled experiments.
        // Sparkle owns preference persistence. Do not overwrite a user's checks/download choice.
        UserDefaults.standard.register(defaults: ["SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false])
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController = controller
        let updater = controller.updater
        updater.sendsSystemProfile = false
        do {
            // Calling the throwing API avoids a startup alert in a misconfigured development app.
            try updater.start()
            updateConfigured = true
            updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshUpdateState() }
                .store(in: &observations)
            updater.publisher(for: \.automaticallyChecksForUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshUpdateState() }
                .store(in: &observations)
            updater.publisher(for: \.automaticallyDownloadsUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshUpdateState() }
                .store(in: &observations)
            refreshUpdateState()
        } catch {
            updaterController = nil
            updateStatus = String(localized: "Updates are unavailable: \(error.localizedDescription)")
        }
    }

    private func refreshUpdateState() {
        guard updateConfigured, let updater = updaterController?.updater else { return }
        automaticChecks = updater.automaticallyChecksForUpdates
        automaticDownloads = updater.automaticallyDownloadsUpdates
        canCheckForUpdates = updater.canCheckForUpdates
        updateStatus = automaticChecks ? String(localized: "Automatic update checks are on.") : String(localized: "Check manually or enable automatic update checks.")
    }
#endif
}
