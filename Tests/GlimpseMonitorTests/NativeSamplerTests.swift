import XCTest
import Darwin
import GlimpseCore
@testable import GlimpseMonitor

final class NativeSamplerTests: XCTestCase {
    func testPerCoreTicksReturnsOneBaselinePerLogicalCore() throws {
        let cores = try NativeSystemReader.perCoreTicks()
        XCTAssertEqual(cores.count, ProcessInfo.processInfo.activeProcessorCount)
        XCTAssertFalse(cores.isEmpty)
        // Tick buckets are monotonic counters; every bucket must be present.
        for ticks in cores {
            XCTAssertGreaterThan(ticks.user + ticks.system + ticks.idle, 0)
        }
    }

    func testConnectionMetadataIsCollectedOnlyForOptedInCardsOrSettings() {
        var now: TimeInterval = 1
        var metadataReads = 0
        let info = NetworkInterfaceInfo(name: "en0", displayName: "Wi-Fi", kind: "Wi-Fi", isUp: true, isRunning: true)
        let sampler = NativeSampler(networkReader: {
            [InterfaceCounter(name: "en0", index: 1, flags: Int32(IFF_UP | IFF_RUNNING), received: 100, sent: 10)]
        }, clock: { now }, physicalReader: { ["en0"] }, primaryReader: { "en0" }, metadataReader: { _ in
            metadataReads += 1
            return [info]
        })
        var settings = AppSettings()
        settings.panels = [PanelConfiguration(metric: .download)]
        XCTAssertTrue(sampler.sample(settings: settings, detailVisible: true).interfaceDetails.isEmpty)
        XCTAssertEqual(metadataReads, 0)
        settings.panels[0].appearance.showsConnectionDetails = true
        now = 2
        XCTAssertEqual(sampler.sample(settings: settings, detailVisible: true).interfaceDetails, [info])
        XCTAssertEqual(metadataReads, 1)
        settings.panels[0].appearance.showsConnectionDetails = false
        now = 3
        XCTAssertTrue(sampler.sample(settings: settings, detailVisible: true).interfaceDetails.isEmpty)
        XCTAssertEqual(metadataReads, 1)
        XCTAssertEqual(sampler.sample(settings: settings, detailVisible: false, configurationVisible: true).interfaceDetails, [info])
        XCTAssertEqual(metadataReads, 1)
    }

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
        settings.columns[2].networkInterface = "utun99"
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

    func testMultipleInterfacesShareOneReadAndKeepIndependentElapsedTimeAndBaselines() {
        var now: TimeInterval = 10
        var reads = 0
        let sampler = NativeSampler(networkReader: {
            reads += 1
            return [
                InterfaceCounter(name: "en0", index: 1, flags: Int32(IFF_UP | IFF_RUNNING), received: UInt64(reads * 100), sent: UInt64(reads * 20)),
                InterfaceCounter(name: "en1", index: 2, flags: Int32(IFF_UP | IFF_RUNNING), received: UInt64(reads * 300), sent: UInt64(reads * 80))
            ]
        }, clock: { now }, physicalReader: { ["en0", "en1"] }, primaryReader: { "en0" })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .download, colour: .blue), ColumnConfiguration(metric: .upload, colour: .mint)]
        settings.columns[1].networkInterface = "en1"
        XCTAssertNil(sampler.sample(settings: settings, detailVisible: false).networkReading(for: .download, interface: nil)?.value)
        now = 12
        let second = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(second.networkReading(for: .download, interface: nil)?.value, 50)
        XCTAssertEqual(second.networkReading(for: .download, interface: "en1")?.value, 150)
        XCTAssertEqual(second.networkReading(for: .upload, interface: "en1")?.value, 40)
        // Drop en1 demand without resetting en0. Returning en1 must re-baseline.
        settings.columns.removeLast()
        now = 14
        let third = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(Set(third.networkReadings.keys), ["en0"])
        XCTAssertEqual(third.networkReading(for: .download, interface: nil)?.value, 50)
        settings.columns.append(ColumnConfiguration(metric: .download, colour: .mint))
        settings.columns[1].networkInterface = "en1"
        now = 16
        let fourth = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(fourth.networkReading(for: .download, interface: nil)?.value, 50)
        XCTAssertNil(fourth.networkReading(for: .download, interface: "en1")?.value)
    }

    func testMetadataDoesNotPollWhenHiddenAndSettingsInventoryDoesNotCreateRates() {
        var now: TimeInterval = 10
        var metadataReads = 0
        let sampler = NativeSampler(networkReader: { [self.fixture("en0", index: 1), self.fixture("en1", index: 2, flags: 0)] },
                                    clock: { now }, physicalReader: { ["en0"] }, primaryReader: { "en0" },
                                    metadataReader: { counters in
            metadataReads += 1
            return counters.map { NetworkInterfaceInfo(name: $0.name, displayName: $0.name, kind: "Wired", isUp: $0.usable, isRunning: $0.usable) }
        })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .memory, colour: .mint)]
        let configuring = sampler.sample(settings: settings, detailVisible: false, configurationVisible: true)
        XCTAssertEqual(configuring.availableInterfaces, ["en0", "en1"])
        XCTAssertEqual(configuring.interfaceDetails.count, 2)
        XCTAssertEqual(configuring.automaticNetworkInterface, "en0")
        XCTAssertEqual(configuring.networkInfo(for: nil)?.name, "en0")
        XCTAssertTrue(configuring.networkReadings.isEmpty)
        XCTAssertEqual(metadataReads, 1)
        now = 11
        _ = sampler.sample(settings: settings, detailVisible: false, configurationVisible: true)
        XCTAssertEqual(metadataReads, 1)
        now = 30
        let hidden = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertTrue(hidden.interfaceDetails.isEmpty)
        XCTAssertEqual(metadataReads, 1)
        settings.columns[0].metric = .download
        let resumed = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertNil(resumed.networkReading(for: .download, interface: nil)?.value)
        XCTAssertEqual(metadataReads, 1)
    }

    func testAutoAndExplicitSameInterfaceUpdateBaselineOnceAndMissingExplicitNeverFallsBack() {
        var now: TimeInterval = 1
        let sampler = NativeSampler(networkReader: { [InterfaceCounter(name: "en0", index: 1, flags: Int32(IFF_UP | IFF_RUNNING), received: UInt64(now * 100), sent: 20)] },
                                    clock: { now }, physicalReader: { ["en0"] }, primaryReader: { "en0" })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .download, colour: .blue), ColumnConfiguration(metric: .upload, colour: .mint), ColumnConfiguration(metric: .download, colour: .mint)]
        settings.columns[1].networkInterface = "en0"
        settings.columns[2].networkInterface = "en9"
        _ = sampler.sample(settings: settings, detailVisible: false)
        now = 3
        let second = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(second.networkReading(for: .download, interface: nil)?.value, 100)
        XCTAssertEqual(second.networkReading(for: .download, interface: "en0")?.value, 100)
        XCTAssertNil(second.networkReading(for: .download, interface: "en9")?.value)
        XCTAssertFalse(second.networkReading(for: .download, interface: "en9")?.detail.isEmpty ?? true)
    }

    func testCounterResetAffectsOnlyItsInterfaceAndReadFailureResetsAllDemandedInterfaces() {
        var now: TimeInterval = 1
        var fail = false
        let sampler = NativeSampler(networkReader: {
            if fail { throw NativeReadError.system("Fixture", EIO) }
            return [
                InterfaceCounter(name: "en0", index: 1, flags: Int32(IFF_UP | IFF_RUNNING), received: now < 3 ? 100 : UInt64(now), sent: 20),
                InterfaceCounter(name: "en1", index: 2, flags: Int32(IFF_UP | IFF_RUNNING), received: UInt64(now * 300), sent: UInt64(now * 80))
            ]
        }, clock: { now }, physicalReader: { ["en0", "en1"] }, primaryReader: { "en0" })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .download, colour: .blue), ColumnConfiguration(metric: .download, colour: .mint)]
        settings.columns[1].networkInterface = "en1"
        _ = sampler.sample(settings: settings, detailVisible: false)
        now = 3
        let reset = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertNil(reset.networkReading(for: .download, interface: nil)?.value)
        XCTAssertEqual(reset.networkReading(for: .download, interface: "en1")?.value, 300)
        fail = true
        now = 4
        let failure = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertNil(failure.networkReading(for: .download, interface: "en1")?.value)
        fail = false
        now = 5
        let recovered = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertNil(recovered.networkReading(for: .download, interface: nil)?.value)
        XCTAssertNil(recovered.networkReading(for: .download, interface: "en1")?.value)
        now = 6
        XCTAssertEqual(sampler.sample(settings: settings, detailVisible: false).networkReading(for: .download, interface: "en1")?.value, 300)
        sampler.resetBaselines()
        now = 7
        XCTAssertNil(sampler.sample(settings: settings, detailVisible: false).networkReading(for: .download, interface: "en1")?.value)
    }

    func testDNSConfigurationStaysWithItsServiceInterfaceAndDoesNotClaimVisitedDomains() {
        let values: [String: Any] = [
            "State:/Network/Service/wifi/IPv4": ["InterfaceName": "en0"],
            "State:/Network/Service/wifi/DNS": ["ServerAddresses": ["192.0.2.53"], "SearchDomains": ["office.example"]],
            "State:/Network/Service/wired/IPv6": ["InterfaceName": "en1"],
            "State:/Network/Service/wired/DNS": ["ServerAddresses": ["2001:db8::53"], "SearchDomains": ["wired.example"], "SupplementalMatchDomains": ["vpn.example"]],
            "State:/Network/Global/DNS": ["ServerAddresses": ["203.0.113.53"], "SearchDomains": ["global.example"]],
            "State:/Network/Service/orphan/DNS": ["ServerAddresses": ["198.51.100.53"]]
        ]
        let result = DNSConfiguration.byInterface(storeValues: values)
        XCTAssertEqual(result["en0"]?.servers, ["192.0.2.53"])
        XCTAssertEqual(result["en0"]?.searchDomains, ["office.example"])
        XCTAssertEqual(result["en1"]?.servers, ["2001:db8::53"])
        XCTAssertEqual(result["en1"]?.searchDomains, ["wired.example"])
        XCTAssertEqual(Set(result.keys), ["en0", "en1"])
    }

    func testVisibleDuplicateNetworkCardsDemandTheirOwnInterfacesAndClosingPanelDropsOnlyThoseBaselines() {
        var now: TimeInterval = 1
        let sampler = NativeSampler(networkReader: {
            ["en0", "en1", "en2"].enumerated().map { index, name in
                InterfaceCounter(name: name, index: UInt32(index + 1), flags: Int32(IFF_UP | IFF_RUNNING),
                                 received: UInt64(now * Double((index + 1) * 100)), sent: 0)
            }
        }, clock: { now }, physicalReader: { ["en0", "en1", "en2"] }, primaryReader: { "en0" }, metadataReader: { _ in [] })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .download, colour: .blue)]
        settings.panels = [PanelConfiguration(metric: .download, networkInterface: "en1"), PanelConfiguration(metric: .download, networkInterface: "en2")]
        XCTAssertEqual(Set(sampler.sample(settings: settings, detailVisible: false).networkReadings.keys), ["en0"])
        now = 2
        let opened = sampler.sample(settings: settings, detailVisible: true)
        XCTAssertEqual(Set(opened.networkReadings.keys), ["en0", "en1", "en2"])
        XCTAssertNil(opened.networkReading(for: .download, interface: "en1")?.value)
        now = 3
        let next = sampler.sample(settings: settings, detailVisible: true)
        XCTAssertEqual(next.networkReading(for: .download, interface: "en1")?.value, 200)
        XCTAssertEqual(next.networkReading(for: .download, interface: "en2")?.value, 300)
        now = 4
        let closed = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(Set(closed.networkReadings.keys), ["en0"])
        XCTAssertEqual(closed.networkReading(for: .download, interface: nil)?.value, 100)
        now = 5
        XCTAssertNil(sampler.sample(settings: settings, detailVisible: true).networkReading(for: .download, interface: "en1")?.value)
    }

    func testLiveNativeReadersAreAvailableWithoutPrivilegesAndFirstRatesAreMissing() throws {
        let sampler = NativeSampler()
        // Connection metadata is opt-in; enable it so this live test still covers
        // privilege-free interface metadata collection.
        var settings = AppSettings()
        if let index = settings.panels.firstIndex(where: { $0.isNetwork }) {
            settings.panels[index].appearance.showsConnectionDetails = true
        }
        let first = sampler.sample(settings: settings, detailVisible: true)
        XCTAssertEqual(Set(first.readings.keys), Set(MetricID.allCases))
        XCTAssertNil(first.readings[.cpu]?.value)
        XCTAssertNil(first.readings[.download]?.value)
        XCTAssertNotNil(first.readings[.memory]?.value, first.readings[.memory]?.detail ?? "")
        XCTAssertNotNil(first.readings[.disk]?.value, first.readings[.disk]?.detail ?? "")
        XCTAssertNotNil(first.readings[.thermal]?.value)
        XCTAssertFalse(first.interfaceDetails.isEmpty)
        let loopback = first.networkInfo(for: "lo0")
        XCTAssertEqual(loopback?.kind, "Loopback")
        XCTAssertTrue(loopback?.ipv4Addresses.contains("127.0.0.1") ?? false)
        let counters = try NativeNetworkReader.readCounters()
        XCTAssertFalse(counters.isEmpty)
        // Mach may return cached CPU ticks for a short interval. Wait for a new
        // measurement rather than assuming a fixed 30 ms sleep advances them.
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var second = sampler.sample(settings: AppSettings(), detailVisible: true)
        while second.readings[.cpu]?.value == nil && ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            second = sampler.sample(settings: AppSettings(), detailVisible: true)
        }
        XCTAssertNotNil(second.readings[.cpu]?.value, second.readings[.cpu]?.detail ?? "")
        if !second.networkInterface.isEmpty {
            XCTAssertNotNil(second.readings[.download]?.value, second.readings[.download]?.detail ?? "")
        }
        sampler.resetBaselines()
        XCTAssertNil(sampler.sample(settings: AppSettings(), detailVisible: true).readings[.cpu]?.value)
    }

    func testAutomaticRateNeverAddsTunnelTrafficToThePhysicalInterface() {
        // A VPN carries the same bytes twice: once inside utun, once encrypted on en0.
        var now: TimeInterval = 10
        var step: UInt64 = 0
        let sampler = NativeSampler(networkReader: {
            [InterfaceCounter(name: "en0", index: 1, flags: Int32(IFF_UP | IFF_RUNNING), received: 1_000 + step * 10_000, sent: 500 + step * 2_000),
             InterfaceCounter(name: "utun4", index: 9, flags: Int32(IFF_UP | IFF_RUNNING), received: 1_000 + step * 9_000, sent: 500 + step * 1_800)]
        }, clock: { now }, physicalReader: { ["en0"] }, primaryReader: { "utun4" }, metadataReader: { _ in [] })
        let settings = AppSettings()
        XCTAssertNil(sampler.sample(settings: settings, detailVisible: false).readings[.download]?.value)
        step = 1; now = 12
        let reading = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertEqual(reading.readings[.download]?.value, 5_000) // en0 only: 10 000 bytes over 2 s
        XCTAssertEqual(reading.automaticNetworkInterface, "en0")
    }

    func testFallbackIgnoresInterfacesWithoutARoutableAddress() {
        // A USB/virtual Ethernet adapter can report UP|RUNNING with no link (owner saw en3 picked with Wi-Fi off).
        let interfaces = [fixture("en0", index: 1), fixture("en3", index: 3)]
        XCTAssertNil(InterfaceSelection.select(interfaces, preferred: nil, primary: nil, physical: ["en0", "en3"], connected: []))
        XCTAssertEqual(InterfaceSelection.select(interfaces, preferred: nil, primary: nil, physical: ["en0", "en3"], connected: ["en3"])?.name, "en3")
        XCTAssertEqual(InterfaceSelection.select(interfaces, preferred: nil, primary: "en0", physical: ["en0", "en3"], connected: [])?.name, "en0")
        XCTAssertEqual(InterfaceSelection.select(interfaces, preferred: "en3", primary: nil, physical: ["en0", "en3"], connected: [])?.name, "en3")
    }

    func testRoutableAddressRules() {
        XCTAssertTrue(NativeNetworkReader.isRoutableIPv4(0xC000_0218))   // 192.0.2.24
        XCTAssertFalse(NativeNetworkReader.isRoutableIPv4(0xA9FE_0101))  // 169.254.1.1 self-assigned
        XCTAssertFalse(NativeNetworkReader.isRoutableIPv4(0x7F00_0001))  // loopback
        XCTAssertFalse(NativeNetworkReader.isRoutableIPv4(0))
        XCTAssertTrue(NativeNetworkReader.isRoutableIPv6(first: 0x20, second: 0x01))  // 2001:db8::
        XCTAssertFalse(NativeNetworkReader.isRoutableIPv6(first: 0xFE, second: 0x80)) // fe80:: link-local
        XCTAssertFalse(NativeNetworkReader.isRoutableIPv6(first: 0, second: 0))       // ::, ::1
    }

    func testSamplerReportsNoInterfaceWhenNothingIsConnected() {
        let sampler = NativeSampler(networkReader: { [self.fixture("en3", index: 3)] }, clock: { 1 },
                                    physicalReader: { ["en3"] }, connectedReader: { [] }, primaryReader: { nil }, metadataReader: { _ in [] })
        XCTAssertNil(sampler.sample(settings: AppSettings(), detailVisible: false).automaticNetworkInterface)
    }

    private func fixture(_ name: String, index: UInt32, flags: Int32 = Int32(IFF_UP | IFF_RUNNING)) -> InterfaceCounter {
        InterfaceCounter(name: name, index: index, flags: flags, received: 100, sent: 200)
    }
}
