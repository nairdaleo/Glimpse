import XCTest
@testable import GlimpseCore

final class GlimpseCoreTests: XCTestCase {
    func testRatesUseMeasuredElapsedTimeAndDoNotTreatMissingOrResetCountersAsZeroTraffic() {
        XCTAssertNil(CounterRate.bytesPerSecond(previous: nil, current: 500, elapsed: 1))
        XCTAssertEqual(CounterRate.bytesPerSecond(previous: 500, current: 1_100, elapsed: 2), 300)
        XCTAssertEqual(CounterRate.bytesPerSecond(previous: 500, current: 1_100, elapsed: 0.5), 1_200)
        XCTAssertEqual(CounterRate.bytesPerSecond(previous: 500, current: 500, elapsed: 1), 0)
        XCTAssertNil(CounterRate.bytesPerSecond(previous: 500, current: 50, elapsed: 1))
        for elapsed in [0, -1, Double.infinity, Double.nan] {
            XCTAssertNil(CounterRate.bytesPerSecond(previous: 500, current: 600, elapsed: elapsed))
        }
    }

    func testCPUUsesDeltasAcrossAllTickCategoriesAndRejectsResets() {
        let previous = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        XCTAssertNil(CPUUsage.percentage(previous: nil, current: previous))
        XCTAssertEqual(CPUUsage.percentage(previous: previous, current: CPUTicks(user: 120, system: 110, idle: 850, nice: 20)), 50)
        XCTAssertNil(CPUUsage.percentage(previous: previous, current: previous))
        XCTAssertNil(CPUUsage.percentage(previous: previous, current: CPUTicks(user: 90, system: 200, idle: 900)))
        XCTAssertEqual(CPUUsage.percentage(previous: CPUTicks(user: 0, system: 0, idle: 0), current: CPUTicks(user: UInt64.max, system: UInt64.max, idle: UInt64.max)) ?? -1, 200.0 / 3, accuracy: 0.00001)
    }

    func testFormattingDistinguishesUnavailableFromZeroAndUsesExplicitDecimalUnits() {
        XCTAssertEqual(MetricPresentation.formatted(value: nil, metric: .download), "—")
        XCTAssertEqual(MetricPresentation.formatted(value: 0, metric: .download), "0 B/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 999, metric: .download), "999 B/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 1_000, metric: .download), "1.0 KB/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 1_000_000, metric: .download), "1.0 MB/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 125, metric: .upload, bits: true), "1.0 Kb/s")
        XCTAssertEqual(MetricPresentation.formatted(value: 34.56, metric: .cpu), "35%")
        XCTAssertEqual(MetricPresentation.formatted(value: 2, metric: .thermal), "Serious")
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(MetricPresentation.formatted(value: value, metric: .cpu), "—")
            XCTAssertNil(MetricPresentation.normalized(value: value, metric: .cpu, networkCeiling: 100))
        }
        XCTAssertEqual(MetricPresentation.formatted(value: -1, metric: .upload), "—")
        XCTAssertLessThan(MetricPresentation.formatted(value: Double.greatestFiniteMagnitude, metric: .download, bits: true).count, 16)
    }

    func testNormalizationClampsFiniteValuesAndRejectsInvalidNetworkScales() {
        XCTAssertEqual(MetricPresentation.normalized(value: 150, metric: .cpu, networkCeiling: 100), 1)
        XCTAssertEqual(MetricPresentation.normalized(value: -5, metric: .memory, networkCeiling: 100), 0)
        XCTAssertEqual(MetricPresentation.normalized(value: 250, metric: .download, networkCeiling: 1_000), 0.25)
        XCTAssertEqual(MetricPresentation.normalized(value: 2, metric: .thermal, networkCeiling: 100), 2.0 / 3)
        XCTAssertNil(MetricPresentation.normalized(value: nil, metric: .battery, networkCeiling: 100))
        for ceiling in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(MetricPresentation.normalized(value: 1, metric: .download, networkCeiling: ceiling))
        }
    }

    func testPartialSettingsKeepKnownValuesAndSupplyMissingDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showBandwidth":true,"columns":[{"metric":"battery","thresholdDirection":"below","warningThreshold":20}]}"#.utf8))
        XCTAssertTrue(settings.showBandwidth)
        XCTAssertEqual(settings.columns.count, 1)
        XCTAssertEqual(settings.columns[0].metric, .battery)
        XCTAssertEqual(settings.columns[0].warningThreshold, 20)
        XCTAssertEqual(settings.columns[0].thresholdDirection, .below)
        XCTAssertEqual(MetricPresentation.normalized(value: 6_250_000, metric: .download, networkCeiling: settings.networkCeiling), 0.5)
        XCTAssertEqual(settings.refreshInterval, 1)
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(roundTrip.columns[0].metric, .battery)
        XCTAssertTrue(roundTrip.showBandwidth)
    }

    func testCorruptedSettingsAreRepairedToUsableBoundedValues() throws {
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showBandwidth":"bad","refreshInterval":-2,"networkCeiling":0,"networkInterface":"  ","columns":[{"metric":"futureMetric","colour":"futureColour"}]}"#.utf8))
        settings.columns.append(ColumnConfiguration(metric: .download, colour: .pink, warningThreshold: .nan, criticalThreshold: -10))
        settings.refreshInterval = .infinity
        settings.networkCeiling = .nan
        settings = settings.validated()
        XCTAssertEqual(settings.columns.count, 2)
        XCTAssertFalse(settings.showBandwidth)
        XCTAssertTrue(settings.refreshInterval.isFinite && settings.refreshInterval >= 1 && settings.refreshInterval <= 60)
        XCTAssertTrue(settings.networkCeiling.isFinite && settings.networkCeiling > 0)
        XCTAssertNil(settings.networkInterface)
        XCTAssertNil(settings.columns[1].warningThreshold)
        XCTAssertNil(settings.columns[1].criticalThreshold)
        settings.columns = [ColumnConfiguration(metric: .cpu, colour: .blue, warningThreshold: 90, criticalThreshold: 50)]
        settings.refreshInterval = 0.001
        settings = settings.validated()
        XCTAssertEqual(settings.refreshInterval, 1)
        XCTAssertEqual(settings.columns[0].warningThreshold, 50)
        XCTAssertEqual(settings.columns[0].criticalThreshold, 90)
    }

    func testHistoryKeepsMissingReadingsAsGapsAndSkipsCachedReadingTimestamps() {
        var history = MetricHistory()
        history.append(snapshot(0, .cpu, 10))
        history.append(snapshot(1, .cpu, nil))
        history.append(Snapshot(timestamp: 2, readings: [.cpu: MetricReading(value: nil, detail: "Cached", timestamp: 1)]))
        history.append(snapshot(3, .cpu, 30))
        XCTAssertEqual(history.samples[.cpu]?.map(\.timestamp), [0, 1, 3])
        XCTAssertEqual(history.samples[.cpu]?[0].value, 10)
        XCTAssertNil(history.samples[.cpu]?[1].value)
        XCTAssertEqual(history.samples[.cpu]?[2].value, 30)
    }

    func testHistoryInsertsOneGapWhenCollectionStopsBeforeResuming() {
        var history = MetricHistory()
        history.append(snapshot(0, .memory, 40))
        history.append(Snapshot(timestamp: 1))
        history.append(Snapshot(timestamp: 2))
        history.append(Snapshot(timestamp: 3, readings: [.memory: MetricReading(value: 40, detail: "Cached", timestamp: 0)]))
        history.append(snapshot(30, .memory, 45))
        history.append(Snapshot(timestamp: 20))
        XCTAssertEqual(history.samples[.memory]?.map(\.timestamp), [0, 1, 30])
        XCTAssertEqual(history.samples[.memory]?.map(\.value), [40, nil, 45])
    }

    func testHistoryBoundsTimeAndSampleCountAndPrunesMetricsNoLongerCollected() {
        var history = MetricHistory()
        history.append(snapshot(0, .battery, 90))
        for index in 0...1_000 { history.append(snapshot(Double(index) / 10, .cpu, Double(index))) }
        XCTAssertEqual(history.samples[.cpu]?.count, 600)
        XCTAssertEqual(history.samples[.cpu]?.first?.timestamp, 40.1)
        history.append(snapshot(400, .cpu, 5))
        XCTAssertEqual(history.samples[.cpu]?.map(\.timestamp), [100, 400])
        XCTAssertTrue(history.samples[.battery]?.isEmpty ?? true)
        history.append(snapshot(399, .cpu, 99))
        history.append(snapshot(.nan, .cpu, 99))
        XCTAssertEqual(history.samples[.cpu]?.map(\.timestamp), [100, 400])
    }

    private func snapshot(_ timestamp: TimeInterval, _ metric: MetricID, _ value: Double?) -> Snapshot {
        Snapshot(timestamp: timestamp, readings: [metric: MetricReading(value: value, detail: "", timestamp: timestamp)])
    }
}
