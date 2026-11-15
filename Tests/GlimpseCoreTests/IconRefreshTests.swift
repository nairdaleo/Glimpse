import XCTest
@testable import GlimpseCore

final class IconRefreshTests: XCTestCase {
    private let base = [MeterState(fill: 0.30, level: .normal), MeterState(fill: nil, level: nil)]

    func testFirstDrawAndLayoutChangesRedraw() {
        XCTAssertTrue(IconRefresh.needsRedraw(shown: nil, next: base))
        XCTAssertTrue(IconRefresh.needsRedraw(shown: base, next: [base[0]]))
    }

    func testSmallMovementIsSkipped() {
        XCTAssertFalse(IconRefresh.needsRedraw(shown: base, next: [MeterState(fill: 0.34, level: .normal), base[1]]))
        XCTAssertFalse(IconRefresh.needsRedraw(shown: base, next: [MeterState(fill: 0.25, level: .normal), base[1]]))
    }

    func testVisibleMovementRedraws() {
        XCTAssertTrue(IconRefresh.needsRedraw(shown: base, next: [MeterState(fill: 0.36, level: .normal), base[1]]))
    }

    func testLevelOrAvailabilityChangeRedraws() {
        XCTAssertTrue(IconRefresh.needsRedraw(shown: base, next: [MeterState(fill: 0.30, level: .warning), base[1]]))
        XCTAssertTrue(IconRefresh.needsRedraw(shown: base, next: [base[0], MeterState(fill: 0, level: nil)]))
        XCTAssertTrue(IconRefresh.needsRedraw(shown: base, next: [MeterState(fill: nil, level: .normal), base[1]]))
    }
}
