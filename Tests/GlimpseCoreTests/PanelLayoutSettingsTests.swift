import XCTest
@testable import GlimpseCore

final class PanelLayoutSettingsTests: XCTestCase {
    func testPanelLayoutSurvivesSettingsRoundTripAlongsideDuplexAndPanelOrder() throws {
        let data = Data(#"{"columns":[{"metric":"download","colour":"orange","isCombinedNetwork":true,"secondaryColour":"purple"}],"panelMetrics":["thermal","cpu"],"panelColumns":5,"panelCardWidth":190,"panelAppearances":{"thermal":{"size":"large","colour":"pink","showsHistory":false}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        let encoded = try JSONEncoder().encode(settings)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(saved["panelColumns"] as? Int, 5)
        XCTAssertEqual(saved["panelCardWidth"] as? Double, 190)
        let appearances = saved["panelAppearances"] as? [String: [String: Any]]
        XCTAssertEqual(appearances?["thermal"]?["size"] as? String, "large")
        XCTAssertEqual(appearances?["thermal"]?["colour"] as? String, "pink")
        XCTAssertEqual(appearances?["thermal"]?["showsHistory"] as? Bool, false)
        let restored = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(restored.columns, settings.columns)
        XCTAssertEqual(restored.panelMetrics, [.thermal, .cpu])
        XCTAssertTrue(restored.columns[0].isCombinedNetwork)
        XCTAssertEqual(restored.columns[0].secondaryColour, .purple)
    }

    func testLegacyAndPartialAppearanceDocumentsSupplyDefaultsWithoutChangingLayouts() throws {
        let legacy = Data(#"{"columns":[{"metric":"battery","colour":"pink"}],"panelMetrics":["battery","cpu"]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(settings.columns.map(\.metric), [.battery])
        XCTAssertEqual(settings.panelMetrics, [.battery, .cpu])
        XCTAssertEqual(settings.panelColumns, 2)
        XCTAssertEqual(settings.panelCardWidth, 156)
        XCTAssertTrue(settings.panelAppearances.isEmpty)
        XCTAssertEqual(settings.panelAppearance(for: .cpu), PanelAppearance(size: .regular, colour: .blue, showsHistory: true))
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"panelAppearances":{"cpu":{"colour":"orange"}}}"#.utf8))
        XCTAssertEqual(partial.panelAppearance(for: .cpu), PanelAppearance(size: .regular, colour: .orange, showsHistory: true))
    }

    func testValidationBoundsColumnsAndCardWidthIncludingNonfiniteInputs() {
        var settings = AppSettings()
        for (input, expected) in [(-5, 1), (0, 1), (1, 1), (8, 8), (9, 8), (Int.max, 8)] {
            settings.panelColumns = input
            XCTAssertEqual(settings.validated().panelColumns, expected)
        }
        let widths: [(Double, Double)] = [(-1, 120), (119, 120), (120, 120), (190, 190), (240, 240), (500, 240), (.nan, 188), (.infinity, 188), (-.infinity, 188)]
        for (input, expected) in widths {
            settings.panelCardWidth = input
            XCTAssertEqual(settings.validated().panelCardWidth, expected)
        }
    }

    func testValidationKeepsKnownLegacyAppearanceKeysForUnselectedMetrics() {
        var settings = AppSettings()
        let custom = PanelAppearance(size: .compact, colour: .orange, showsHistory: false)
        settings.panelMetrics = []
        settings.panelAppearances = ["cpu": custom, "futureMetric": PanelAppearance(size: .large, colour: .pink)]
        let validated = settings.validated()
        XCTAssertEqual(Set(validated.panelAppearances.keys), ["cpu"])
        XCTAssertEqual(validated.panelAppearance(for: .cpu), custom)
        XCTAssertEqual(validated.panelAppearance(for: .download), PanelAppearance())
        XCTAssertTrue(validated.panelMetrics.isEmpty)
    }

    func testMalformedAppearanceFieldsFallBackIndependentlyAndPreserveKnownValues() throws {
        let data = Data(#"{"panelColumns":"invalid","panelCardWidth":"invalid","panelAppearances":{"cpu":{"size":"future","colour":"orange","showsHistory":false},"memory":{"size":"large","colour":"future","showsHistory":"invalid"},"thermal":null,"futureMetric":{"size":"compact"}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.panelColumns, 2)
        XCTAssertEqual(settings.panelCardWidth, 156)
        XCTAssertEqual(settings.panelAppearance(for: .cpu), PanelAppearance(size: .regular, colour: .orange, showsHistory: false))
        XCTAssertEqual(settings.panelAppearance(for: .memory), PanelAppearance(size: .large, colour: .blue, showsHistory: true))
        XCTAssertEqual(settings.panelAppearance(for: .thermal), PanelAppearance())
        XCTAssertEqual(Set(settings.panelAppearances.keys), ["cpu", "memory", "thermal"])
    }
}

final class CardWidthDefaultTests: XCTestCase {
    func testNewInstallsGetRoomForTranslatedLabels() {
        XCTAssertEqual(AppSettings().panelCardWidth, 188)
    }
}

final class InitialLayoutTests: XCTestCase {
    func testNewInstallsStartWithTheScreenshotLayout() {
        let settings = AppSettings.initial
        XCTAssertEqual(settings.columns.map(\.metric), [.cpu, .memory, .download, .battery])
        XCTAssertTrue(settings.columns[2].isCombinedNetwork)
        XCTAssertEqual(settings.columns[3].colourBands?.gradient, true)
        XCTAssertEqual(settings.panels.map(\.metric), [.cpu, .download, .disk, .battery, .memory])
        XCTAssertEqual(settings.panels.map(\.appearance.size), [.large, .large, .compact, .compact, .regular])
        XCTAssertEqual(settings.panels[0].appearance.largeOrientation, .horizontal)
        XCTAssertTrue(settings.panels[1].isCombinedNetwork && settings.panels[1].appearance.showsConnectionDetails)
        XCTAssertEqual(settings.panelColumns, 3)
        XCTAssertEqual(settings.panelCardWidth, 188)
        XCTAssertEqual(settings.refreshInterval, 2)
        XCTAssertTrue(settings.bandwidthInBits)
        XCTAssertEqual(settings.validated().columns.count, 4) // survives validation unchanged
        XCTAssertEqual(settings.validated().panels.count, 5)
    }
}
