import XCTest
@testable import GlimpseCore

final class PanelAppearanceMigrationTests: XCTestCase {
    func testLegacyAppearanceWritesDefaultsForOrientationAndConnectionDetails() throws {
        let appearance = try JSONDecoder().decode(PanelAppearance.self, from: Data(#"{"size":"large","colour":"orange","showsHistory":false}"#.utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as? [String: Any])
        XCTAssertEqual(object["largeOrientation"] as? String, "vertical")
        XCTAssertEqual(object["showsConnectionDetails"] as? Bool, false)
        XCTAssertEqual(appearance.size, .large)
        XCTAssertEqual(appearance.colour, .orange)
        XCTAssertFalse(appearance.showsHistory)
        XCTAssertEqual(appearance.largeOrientation, .vertical)
        XCTAssertFalse(appearance.showsConnectionDetails)
    }

    func testExplicitOrientationAndConnectionDetailsSurvivePanelSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.panels = [.init(metric: .download, networkInterface: "en7", appearance: .init(size: .large, colour: .orange, showsHistory: false, largeOrientation: .horizontal, showsConnectionDetails: true))]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.panels, settings.panels)
        XCTAssertEqual(restored.panels[0].appearance.largeOrientation, .horizontal)
        XCTAssertTrue(restored.panels[0].appearance.showsConnectionDetails)
    }

    func testMalformedNewAppearanceFieldsFallBackIndependently() throws {
        let data = Data(#"{"size":"compact","colour":"pink","largeOrientation":"future","showsConnectionDetails":"invalid","showsHistory":false}"#.utf8)
        let appearance = try JSONDecoder().decode(PanelAppearance.self, from: data)
        XCTAssertEqual(appearance, PanelAppearance(size: .compact, colour: .pink, showsHistory: false))
        let partial = try JSONDecoder().decode(PanelAppearance.self, from: Data(#"{"showsConnectionDetails":true}"#.utf8))
        XCTAssertEqual(partial.largeOrientation, .vertical)
        XCTAssertTrue(partial.showsConnectionDetails)
        XCTAssertEqual(PanelLargeOrientation.vertical.title, "1 × 2 · Vertical")
        XCTAssertEqual(PanelLargeOrientation.horizontal.title, "2 × 1 · Horizontal")
    }
}
