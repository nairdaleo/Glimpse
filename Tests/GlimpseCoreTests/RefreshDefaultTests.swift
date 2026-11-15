import XCTest
@testable import GlimpseCore

final class RefreshDefaultTests: XCTestCase {
    func testNewInstallsRefreshEveryTwoSeconds() {
        XCTAssertEqual(AppSettings().refreshInterval, 2)
    }

    func testSavedOneSecondChoiceIsKept() throws {
        var settings = AppSettings()
        settings.refreshInterval = 1
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).refreshInterval, 1)
    }
}
