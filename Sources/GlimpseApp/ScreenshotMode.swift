import Foundation

/// `-GlimpseScreenshotMode YES` (a launch argument) shows documentation-only network
/// addresses instead of this Mac's, for store screenshots. Readings stay live.
enum ScreenshotMode {
    static let isOn = UserDefaults.standard.bool(forKey: "GlimpseScreenshotMode")
}
