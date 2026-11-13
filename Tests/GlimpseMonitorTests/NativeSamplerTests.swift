import XCTest
import Darwin
import GlimpseCore
@testable import GlimpseMonitor

final class NativeSamplerTests: XCTestCase {
    func testRateUsesMeasuredTimeAndResetsOnIdentityChangeOrReadFailure() {
        var tracker = InterfaceRateTracker()
        XCTAssertNil(tracker.update(identity: "en0:1", received: 100, sent: 20, timestamp: 10))
        let next = tracker.update(identity: "en0:1", received: 400, sent: 80, timestamp: 12)
        XCTAssertEqual(next?.download, 150)
        XCTAssertEqual(next?.upload, 30)
        XCTAssertNil(tracker.update(identity: "en1:2", received: 10_000, sent: 10_000, timestamp: 13))
        tracker.reset()
        XCTAssertNil(tracker.update(identity: "en1:2", received: 20_000, sent: 20_000, timestamp: 20))
        XCTAssertNil(tracker.update(identity: "en1:2", received: 10, sent: 10, timestamp: 21))
        XCTAssertEqual(tracker.update(identity: "en1:2", received: 30, sent: 50, timestamp: 23)?.download, 10)
        XCTAssertNil(tracker.update(identity: "en1:2", received: 40, sent: 60, timestamp: 23))
    }

    func testAutomaticSelectionExcludesTunnelEvenWhenTunnelIsPrimary() {
        let interfaces = [fixture("utun4", index: 4), fixture("en1", index: 2), fixture("en0", index: 1)]
        XCTAssertEqual(InterfaceSelection.select(interfaces, preferred: nil, primary: "utun4", physical: ["en0", "en1"])?.name, "en0")
        XCTAssertEqual(InterfaceSelection.select(interfaces, preferred: nil, primary: "en1", physical: ["en0", "en1"])?.name, "en1")
        XCTAssertEqual(InterfaceSelection.select(interfaces, preferred: "utun4", primary: "en0", physical: ["en0"])?.name, "utun4")
        XCTAssertNil(InterfaceSelection.select(interfaces, preferred: "missing", primary: "en0", physical: ["en0"]))
    }

    func testAutomaticSelectionDoesNotPickDownOrLoopbackInterfaces() {
        let interfaces = [fixture("en0", index: 1, flags: 0), fixture("lo0", index: 2, flags: Int32(IFF_UP | IFF_LOOPBACK)), fixture("en1", index: 3, flags: Int32(IFF_UP))]
        XCTAssertNil(InterfaceSelection.select(interfaces, preferred: nil, primary: "en0", physical: ["en0", "lo0"]))
        XCTAssertNil(InterfaceSelection.select(interfaces, preferred: nil, primary: "en1", physical: ["en1"]))
    }

    func testRouteParserPreserves64BitCountersAndRejectsTruncatedRecords() throws {
        var header = if_msghdr2()
        header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        header.ifm_version = UInt8(RTM_VERSION)
        header.ifm_type = UInt8(RTM_IFINFO2)
        header.ifm_index = 7
        header.ifm_flags = Int32(IFF_UP)
        header.ifm_data.ifi_ibytes = 9_000_000_000
        header.ifm_data.ifi_obytes = 8_000_000_000
        let data = withUnsafeBytes(of: header) { Data($0) }
        let result = try InterfaceCounterParser.parse(data) { $0 == 7 ? "en7" : nil }
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].received, 9_000_000_000)
        XCTAssertEqual(result[0].sent, 8_000_000_000)
        XCTAssertThrowsError(try InterfaceCounterParser.parse(Data(data.dropLast())) { _ in "en7" })
        XCTAssertThrowsError(try InterfaceCounterParser.parse(Data([0, 0, 0, 0])) { _ in nil })
    }

    func testMemoryAccountingExcludesRecoverableInactiveAndSpeculativePages() {
        XCTAssertEqual(MemoryAccounting.usedBytes(active: 100, inactive: 200, wired: 30, compressed: 20, pageSize: 4096), 614_400)
    }

    func testReadFailureBreaksNetworkBaselineBeforeRecovery() {
        var step = 0
        let sampler = NativeSampler(networkReader: {
            step += 1
            if step == 3 { throw NativeReadError.system("Fixture", EIO) }
            return [InterfaceCounter(name: "utun99", index: 99, flags: Int32(IFF_UP | IFF_RUNNING), received: UInt64(step * 1_000), sent: UInt64(step * 2_000))]
        })
        var settings = AppSettings()
        settings.networkInterface = "utun99"
        XCTAssertNil(sampler.sample(settings: settings, detailVisible: false).readings[.download]?.value)
        XCTAssertNotNil(sampler.sample(settings: settings, detailVisible: false).readings[.download]?.value)
        let failed = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertNil(failed.readings[.download]?.value)
        XCTAssertFalse(failed.readings[.download]?.detail.isEmpty ?? true)
        XCTAssertNil(sampler.sample(settings: settings, detailVisible: false).readings[.download]?.value)
        XCTAssertNotNil(sampler.sample(settings: settings, detailVisible: false).readings[.download]?.value)
    }

    func testDemandStopsNetworkReadsAndSlowReadingKeepsCollectionTimestamp() {
        let sampler = NativeSampler(networkReader: { XCTFail("Undemanded network reader invoked"); return [] })
        var settings = AppSettings()
        settings.columns = Array(repeating: ColumnConfiguration(metric: .memory, colour: .mint), count: 3)
        let first = sampler.sample(settings: settings, detailVisible: false)
        let second = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(Set(first.readings.keys), [.memory])
        XCTAssertEqual(first.readings[.memory]?.timestamp, second.readings[.memory]?.timestamp)
    }

    func testLiveNativeReadersAreAvailableWithoutPrivilegesAndFirstRatesAreMissing() throws {
        let sampler = NativeSampler()
        let first = sampler.sample(settings: AppSettings(), detailVisible: true)
        XCTAssertEqual(Set(first.readings.keys), Set(MetricID.allCases))
        XCTAssertNil(first.readings[.cpu]?.value)
        XCTAssertNil(first.readings[.download]?.value)
        XCTAssertNotNil(first.readings[.memory]?.value, first.readings[.memory]?.detail ?? "")
        XCTAssertNotNil(first.readings[.disk]?.value, first.readings[.disk]?.detail ?? "")
        XCTAssertNotNil(first.readings[.thermal]?.value)
        let counters = try NativeNetworkReader.readCounters()
        XCTAssertFalse(counters.isEmpty)
        Thread.sleep(forTimeInterval: 0.03)
        let second = sampler.sample(settings: AppSettings(), detailVisible: true)
        XCTAssertNotNil(second.readings[.cpu]?.value, second.readings[.cpu]?.detail ?? "")
        if !second.networkInterface.isEmpty {
            XCTAssertNotNil(second.readings[.download]?.value, second.readings[.download]?.detail ?? "")
        }
        sampler.resetBaselines()
        XCTAssertNil(sampler.sample(settings: AppSettings(), detailVisible: true).readings[.cpu]?.value)
    }

    private func fixture(_ name: String, index: UInt32, flags: Int32 = Int32(IFF_UP | IFF_RUNNING)) -> InterfaceCounter {
        InterfaceCounter(name: name, index: index, flags: flags, received: 100, sent: 200)
    }
}
