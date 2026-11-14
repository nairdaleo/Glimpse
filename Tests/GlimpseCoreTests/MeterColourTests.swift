import XCTest
@testable import GlimpseCore

final class MeterColourTests: XCTestCase {
    func testCustomRGBObjectsPersistForBothMeterHalvesAndCardHistory() throws {
        let data = Data(#"{"columns":[{"metric":"download","isCombinedNetwork":true,"colour":{"red":0.125,"green":0.5,"blue":0.875},"secondaryColour":{"red":0.75,"green":0.25,"blue":0.5}}],"panelAppearances":{"cpu":{"colour":{"red":0.25,"green":0.75,"blue":0.125}}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        let encoded = try JSONEncoder().encode(settings)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let column = try XCTUnwrap((saved["columns"] as? [[String: Any]])?.first)
        XCTAssertEqual((column["colour"] as? [String: Double])?["red"], 0.125)
        XCTAssertEqual((column["secondaryColour"] as? [String: Double])?["green"], 0.25)
        let appearances = saved["panelAppearances"] as? [String: [String: Any]]
        XCTAssertEqual((appearances?["cpu"]?["colour"] as? [String: Double])?["blue"], 0.125)
        let restored = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(restored.columns, settings.columns)
        XCTAssertEqual(restored.panelAppearances, settings.panelAppearances)
    }

    func testEveryLegacyPresetStillDecodesAndEncodesAsTheSameString() throws {
        for name in ["mint", "blue", "purple", "orange", "pink"] {
            let decoded = try JSONDecoder().decode(MeterColour.self, from: JSONEncoder().encode(name))
            XCTAssertEqual(decoded, MeterColour(rawValue: name))
            XCTAssertEqual(try JSONDecoder().decode(String.self, from: JSONEncoder().encode(decoded)), name)
        }
    }

    func testCustomComponentsClampAndRemainHashableWithNonfiniteInput() throws {
        let clamped = MeterColour.custom(red: -0.5, green: 0.25, blue: 2)
        XCTAssertEqual(clamped, .custom(red: 0, green: 0.25, blue: 1))
        let nonfinite = MeterColour.custom(red: .nan, green: .infinity, blue: -.infinity)
        let black = MeterColour.custom(red: 0, green: 0, blue: 0)
        XCTAssertEqual(Set([nonfinite, black]).count, 1)
        XCTAssertEqual(MeterColour(rawValue: clamped.rawValue), clamped)
        let decoded = try JSONDecoder().decode(MeterColour.self, from: Data(#"{"red":-1,"green":0.5,"blue":2}"#.utf8))
        XCTAssertEqual(decoded, .custom(red: 0, green: 0.5, blue: 1))
        XCTAssertEqual(try JSONDecoder().decode(MeterColour.self, from: JSONEncoder().encode(nonfinite)), black)
    }

    func testMalformedCustomColourDoesNotDiscardValidLegacySettings() throws {
        let data = Data(#"{"columns":[{"metric":"battery","colour":{"red":"bad","green":0.5,"blue":0.5},"secondaryColour":"pink","warningThreshold":20}],"panelAppearances":{"cpu":{"colour":{"red":0.25,"green":0.5,"blue":0.75}}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.columns[0].colour, .mint)
        XCTAssertEqual(settings.columns[0].secondaryColour, .pink)
        XCTAssertEqual(settings.columns[0].warningThreshold, 20)
        XCTAssertEqual(settings.panelAppearance(for: .cpu).colour, .custom(red: 0.25, green: 0.5, blue: 0.75))
    }

    func testGreenIsASuggestedPresetThatRoundTrips() throws {
        XCTAssertTrue(MeterColour.allCases.contains(.green))
        XCTAssertEqual(MeterColour(rawValue: "green"), .green)
        XCTAssertEqual(try JSONDecoder().decode(MeterColour.self, from: JSONEncoder().encode(MeterColour.green)), .green)
    }
}
