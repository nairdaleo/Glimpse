import XCTest
@testable import GlimpseCore

final class NetworkDisplaySettingsTests: XCTestCase {
    func testLegacySettingsWriteIdentityBearingPanelsAndExplicitAutomaticInterfaces() throws {
        let data = Data(#"{"networkInterface":"en7","panelMetrics":["upload","cpu"],"panelAppearances":{"upload":{"colour":"orange"}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        let encoded = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let panels = try XCTUnwrap(object["panels"] as? [[String: Any]])
        XCTAssertEqual(panels.map { $0["metric"] as? String }, ["upload", "cpu"])
        XCTAssertEqual(panels[0]["networkInterface"] as? String, "en7")
        XCTAssertNotNil(panels[0]["id"])
        XCTAssertTrue(panels[1]["networkInterface"] is NSNull)
    }

    func testOnlyMissingLegacyColumnInterfacesInheritGlobalSelection() throws {
        let data = Data(#"{"networkInterface":"en7","columns":[{"metric":"download"},{"metric":"upload","networkInterface":null},{"metric":"download","networkInterface":"en9"},{"metric":"cpu"}]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.columns.map(\.networkInterface), ["en7", nil, "en9", nil])
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.columns, settings.columns)
        XCTAssertEqual(restored.panels, settings.panels)
    }

    func testLegacyEmptyLayoutPreservesEmptySelectionAndLegacyAppearanceData() throws {
        let data = Data(#"{"panelMetrics":[],"networkInterface":"utun3","panelAppearances":{"upload":{"size":"large","colour":"orange","showsHistory":false}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(settings.panels.isEmpty)
        XCTAssertEqual(settings.panelAppearance(for: .upload), PanelAppearance(size: .large, colour: .orange, showsHistory: false))
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(restored.panels.isEmpty)
    }

    func testRepeatedNetworkPanelsKeepIndependentIdentityAppearanceAndInterfaceWhenReordered() throws {
        var settings = AppSettings()
        settings.panels = []
        let first = try XCTUnwrap(WidgetOrganization.addPanel(to: &settings, metric: .download, networkInterface: "en0"))
        let second = try XCTUnwrap(WidgetOrganization.addPanel(to: &settings, metric: .download, isCombinedNetwork: true, networkInterface: "en0", appearance: PanelAppearance(size: .compact, colour: .pink)))
        let third = try XCTUnwrap(WidgetOrganization.addPanel(to: &settings, metric: .download, networkInterface: "en9"))
        let original = settings.panels
        XCTAssertEqual(Set(original.map(\.id)).count, 3)
        XCTAssertTrue(WidgetOrganization.movePanel(in: &settings, id: third, before: first))
        XCTAssertEqual(settings.panels, [original[2], original[0], original[1]])
        XCTAssertTrue(WidgetOrganization.removePanel(from: &settings, id: second))
        var restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.panels, settings.panels)
        XCTAssertFalse(restored.panels.contains { $0.id == second })
        XCTAssertTrue(WidgetOrganization.removePanel(from: &restored, id: first))
        XCTAssertFalse(WidgetOrganization.removePanel(from: &restored, id: first))
    }

    func testNewAutomaticPanelsDoNotInheritLegacyGlobalSelection() throws {
        let data = Data(#"{"networkInterface":"en7","panels":[{"metric":"upload","networkInterface":null},{"metric":"download","networkInterface":"  en9 "},{"metric":"cpu","networkInterface":"en0"}]}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.panels.map(\.networkInterface), [nil, "en9", nil])
        XCTAssertEqual(settings.panels[0].requiredMetrics, [.upload])
        let combined = PanelConfiguration(metric: .cpu, isCombinedNetwork: true)
        XCTAssertEqual(combined.requiredMetrics, [.upload, .download])
        XCTAssertEqual(combined.displayTitle, "Upload / Download")
        XCTAssertTrue(combined.isNetwork)
    }

    func testValidationRepairsIdentityCollisionsAndBoundsPanelCount() {
        var settings = AppSettings()
        let panel = PanelConfiguration(metric: .download, networkInterface: "en0")
        settings.panels = Array(repeating: panel, count: 40)
        let validated = settings.validated()
        XCTAssertEqual(validated.panels.count, 32)
        XCTAssertEqual(validated.panels[0].id, panel.id)
        XCTAssertEqual(Set(validated.panels.map(\.id)).count, 32)
        XCTAssertEqual(validated.validated().panels, validated.panels)
        settings = validated
        XCTAssertNil(WidgetOrganization.addPanel(to: &settings, metric: .cpu))
        XCTAssertTrue(WidgetOrganization.removePanel(from: &settings, id: panel.id))
        XCTAssertNotNil(WidgetOrganization.addPanel(to: &settings, metric: .cpu))
    }

    func testLegacyMetricSetterPreservesExistingPanelsAndDoesNotRestoreRemovedIdentities() {
        var settings = AppSettings()
        let original = settings.panels[0]
        let download = settings.panels.first { $0.metric == .download }
        settings.panelMetrics = [.memory, .download]
        settings.panelMetrics = [.download, .cpu, .cpu]
        XCTAssertEqual(settings.panelMetrics, [.download, .cpu])
        XCTAssertEqual(settings.panels.first, download)
        XCTAssertNotEqual(settings.panels.last?.id, original.id)
    }
}
