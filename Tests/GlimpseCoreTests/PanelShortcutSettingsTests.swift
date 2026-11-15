import XCTest
@testable import GlimpseCore

final class PanelShortcutSettingsTests: XCTestCase {
    func testDefaultsToNoShortcut() {
        XCTAssertNil(AppSettings().panelShortcut)
    }

    func testLegacySettingsWithoutShortcutDecode() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
        legacy["panelShortcut"] = nil
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.panelShortcut)
    }

    func testShortcutRoundTrips() throws {
        var settings = AppSettings()
        settings.panelShortcut = KeyboardShortcut(keyCode: 5, modifiers: 0x1000 | 0x0800, display: "⌃⌥G")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.panelShortcut, settings.panelShortcut)
    }
}
