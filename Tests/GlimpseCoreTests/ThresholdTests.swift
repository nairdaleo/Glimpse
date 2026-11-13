import XCTest
@testable import GlimpseCore

final class ThresholdTests: XCTestCase {
    func testDeadbandCannotPreventReleaseAtZeroTrafficOrFullBattery() {
        let network = ColumnConfiguration(metric: .download, colour: .blue, warningThreshold: 80_000, criticalThreshold: 100_000)
        var traffic = ThresholdLatch()
        XCTAssertEqual(traffic.evaluate(value: 200_000, column: network, deadband: 125_000), .critical)
        XCTAssertEqual(traffic.evaluate(value: 0, column: network, deadband: 125_000), .normal)

        let battery = ColumnConfiguration(metric: .battery, colour: .mint, warningThreshold: 99.5, criticalThreshold: 99, thresholdDirection: .below)
        var charge = ThresholdLatch()
        XCTAssertEqual(charge.evaluate(value: 98, column: battery, deadband: 1), .critical)
        XCTAssertEqual(charge.evaluate(value: 100, column: battery, deadband: 1), .normal)
    }

    func testWarningDoesNotFlickerNearBoundaryAndCriticalEscalatesImmediately() {
        let column = ColumnConfiguration(metric: .cpu, colour: .mint, warningThreshold: 70, criticalThreshold: 90)
        var latch = ThresholdLatch()
        XCTAssertEqual(latch.evaluate(value: 70, column: column, deadband: 1), .warning)
        XCTAssertEqual(latch.evaluate(value: 69.5, column: column, deadband: 1), .warning)
        XCTAssertEqual(latch.evaluate(value: 90, column: column, deadband: 1), .critical)
        XCTAssertEqual(latch.evaluate(value: 89.5, column: column, deadband: 1), .critical)
        XCTAssertEqual(latch.evaluate(value: 88, column: column, deadband: 1), .warning)
        XCTAssertEqual(latch.evaluate(value: 68, column: column, deadband: 1), .normal)
    }

    func testLowBatteryDirectionAndUnavailableOrReconfiguredValuesResetLatch() {
        var column = ColumnConfiguration(metric: .battery, colour: .blue, warningThreshold: 30, criticalThreshold: 10, thresholdDirection: .below)
        var latch = ThresholdLatch()
        XCTAssertEqual(latch.evaluate(value: 10, column: column, deadband: 1), .critical)
        XCTAssertEqual(latch.evaluate(value: 10.5, column: column, deadband: 1), .critical)
        XCTAssertNil(latch.evaluate(value: nil, column: column, deadband: 1))
        XCTAssertEqual(latch.evaluate(value: 10.5, column: column, deadband: 1), .warning)
        column.warningThreshold = 5
        column.criticalThreshold = 2
        XCTAssertEqual(latch.evaluate(value: 10.5, column: column, deadband: 1), .normal)
    }
}
