import XCTest
import Darwin
import GlimpseCore
@testable import GlimpseMonitor

final class DemandTests: XCTestCase {
    func testVisibleDetailCollectsOnlyEnabledPanelsAndIconMetrics() {
        let sampler = NativeSampler(networkReader: { XCTFail("Hidden network panels must not poll"); return [] })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .cpu, colour: .mint)]
        settings.panelMetrics = [.thermal]
        XCTAssertEqual(Set(sampler.sample(settings: settings, detailVisible: true).readings.keys), [.cpu, .thermal])
        settings.panelMetrics = []
        settings.columns = [ColumnConfiguration(metric: .memory, colour: .mint)]
        XCTAssertEqual(Set(sampler.sample(settings: settings, detailVisible: true).readings.keys), [.memory])
    }

    func testConfigurationEnumeratesInterfacesWithoutPublishingOrBaseliningHiddenNetwork() {
        var reads = 0
        let sampler = NativeSampler(networkReader: {
            reads += 1
            return [InterfaceCounter(name: "utun99", index: 99, flags: Int32(IFF_UP | IFF_RUNNING), received: UInt64(reads * 1_000), sent: UInt64(reads * 2_000))]
        })
        var settings = AppSettings()
        settings.columns = [ColumnConfiguration(metric: .thermal, colour: .mint)]
        settings.panelMetrics = []
        settings.networkInterface = "utun99"
        let configuration = sampler.sample(settings: settings, detailVisible: false, configurationVisible: true)
        XCTAssertEqual(configuration.availableInterfaces, ["utun99"])
        XCTAssertEqual(Set(configuration.readings.keys), [.thermal])
        let hidden = sampler.sample(settings: settings, detailVisible: true)
        XCTAssertTrue(hidden.availableInterfaces.isEmpty)
        XCTAssertEqual(reads, 1)
        settings.columns = [ColumnConfiguration(metric: .download, colour: .blue)]
        let firstDemand = sampler.sample(settings: settings, detailVisible: false)
        XCTAssertNil(firstDemand.readings[.download]?.value)
        XCTAssertNotNil(sampler.sample(settings: settings, detailVisible: false).readings[.download]?.value)
    }
}
