import XCTest
@testable import GlimpseCore

final class PanelRemovalTests: XCTestCase {
    func testLegacyHiddenPanelsAreNotRetainedOrCountedAgainstCapacity() throws {
        let data = Data(#"{"panels":[{"metric":"cpu"}],"hiddenPanels":[{"metric":"upload","networkInterface":"en9"}]}"#.utf8)
        var settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.panels.map(\.metric), [.cpu])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        XCTAssertNil(object["hiddenPanels"])
        for _ in 1..<32 { XCTAssertNotNil(WidgetOrganization.addPanel(to: &settings, metric: .download)) }
        XCTAssertEqual(settings.panels.count, 32)
    }

    func testRemovingPanelFreesCapacityAndAddingCreatesANewConfiguration() throws {
        var settings = AppSettings()
        settings.panels = (0..<32).map { _ in PanelConfiguration(metric: .upload, networkInterface: "en9") }
        let removed = settings.panels[0]
        XCTAssertNil(WidgetOrganization.addPanel(to: &settings, metric: .download))
        XCTAssertTrue(WidgetOrganization.removePanel(from: &settings, id: removed.id))
        let added = try XCTUnwrap(WidgetOrganization.addPanel(to: &settings, metric: .download))
        XCTAssertNotEqual(added, removed.id)
        XCTAssertNil(settings.panels.first { $0.id == added }?.networkInterface)
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(saved.panels.contains { $0.id == removed.id })
        XCTAssertEqual(saved.panels.count, 32)
    }
}
