import Foundation
import Darwin
import IOKit
import IOKit.ps
import GlimpseCore

/// Mutable sampling state belongs to the application's single sampling queue.
/// This class intentionally has no internal timer and must not be called concurrently.
public final class NativeSampler {
    private var cpuBaseline: CPUTicks?
    private var coreBaselines: [CPUTicks] = []
    private var networkRates: [String: InterfaceRateTracker] = [:]
    private var cache: [MetricID: MetricReading] = [:]
    private var physical: Set<String> = []
    private var primary: String?
    private var networkMetadataTimestamp: TimeInterval = -.infinity
    private var interfaceMetadata: [NetworkInterfaceInfo] = []
    private var interfaceMetadataTimestamp: TimeInterval = -.infinity
    private var metadataCounterNames: Set<String> = []
    private var lastCapacityUnits: CapacityUnits?
    private let readNetworkCounters: () throws -> [InterfaceCounter]
    private let clock: () -> TimeInterval
    private let readPhysicalInterfaces: () -> Set<String>
    private let readConnectedInterfaces: () -> Set<String>
    private let readPrimaryInterface: () -> String?
    private let readMetadata: ([InterfaceCounter]) -> [NetworkInterfaceInfo]

    public convenience init() { self.init(networkReader: NativeNetworkReader.readCounters) }

    internal init(networkReader: @escaping () throws -> [InterfaceCounter],
                  clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                  physicalReader: @escaping () -> Set<String> = NativeNetworkReader.physicalInterfaces,
                  connectedReader: @escaping () -> Set<String> = NativeNetworkReader.connectedInterfaces,
                  primaryReader: @escaping () -> String? = NativeNetworkReader.primaryInterface,
                  metadataReader: @escaping ([InterfaceCounter]) -> [NetworkInterfaceInfo] = NativeNetworkMetadata.read) {
        readNetworkCounters = networkReader
        self.clock = clock
        readPhysicalInterfaces = physicalReader
        readConnectedInterfaces = connectedReader
        readPrimaryInterface = primaryReader
        readMetadata = metadataReader
    }

    public func resetBaselines() {
        cpuBaseline = nil
        coreBaselines = []
        networkRates.removeAll()
        cache.removeAll()
        networkMetadataTimestamp = -.infinity
        interfaceMetadataTimestamp = -.infinity
    }

    public func sample(settings: AppSettings, detailVisible: Bool, configurationVisible: Bool = false) -> Snapshot {
        let settings = settings.validated()
        let now = clock()
        var demanded = Set(settings.columns.flatMap(\.requiredMetrics))
        if detailVisible { demanded.formUnion(settings.panels.flatMap(\.requiredMetrics)) }
        if settings.showBandwidth { demanded.formUnion([.download, .upload]) }
        var readings: [MetricID: MetricReading] = [:]
        var cpuCores: [Double] = []
        if demanded.contains(.cpu) {
            do {
                let ticks = try NativeSystemReader.cpuTicks()
                let value = CPUUsage.percentage(previous: cpuBaseline, current: ticks)
                cpuBaseline = ticks
                readings[.cpu] = MetricReading(value: value, detail: value == nil ? String(localized: "Collecting CPU baseline") : String(localized: "CPU activity across all cores"), timestamp: now)
                let coreTicks = try NativeSystemReader.perCoreTicks()
                if coreBaselines.count == coreTicks.count {
                    cpuCores = zip(coreBaselines, coreTicks).compactMap { CPUUsage.percentage(previous: $0, current: $1) }
                }
                coreBaselines = coreTicks
            } catch {
                cpuBaseline = nil
                coreBaselines = []
                readings[.cpu] = unavailable(error, timestamp: now)
            }
        } else { cpuBaseline = nil; coreBaselines = [] }

        // A capacity-units change must reformat cached memory and disk readings
        // immediately instead of waiting out their refresh intervals.
        if lastCapacityUnits != settings.capacityUnits {
            cache[.memory] = nil
            cache[.disk] = nil
            lastCapacityUnits = settings.capacityUnits
        }

        for (metric, interval) in [(MetricID.memory, 2.0), (.battery, 10), (.disk, 30), (.thermal, 5)] where demanded.contains(metric) {
            if let previous = cache[metric], now - previous.timestamp < interval {
                readings[metric] = previous
                continue
            }
            let reading: MetricReading
            do {
                switch metric {
                case .memory: reading = try NativeSystemReader.memory(timestamp: now, units: settings.capacityUnits)
                case .battery: reading = NativeSystemReader.battery(timestamp: now)
                case .disk: reading = try NativeSystemReader.disk(timestamp: now, units: settings.capacityUnits)
                case .thermal: reading = NativeSystemReader.thermal(timestamp: now)
                default: continue
                }
            } catch { reading = unavailable(error, timestamp: now) }
            cache[metric] = reading
            readings[metric] = reading
        }

        var selections: Set<String?> = []
        for column in settings.columns where column.requiredMetrics.contains(.download) || column.requiredMetrics.contains(.upload) {
            selections.insert(column.networkInterface)
        }
        if detailVisible {
            for panel in settings.panels where panel.isNetwork { selections.insert(panel.networkInterface) }
        }
        if settings.showBandwidth { selections.insert(settings.networkInterface) }
        let networkDemanded = !selections.isEmpty
        var interface = ""
        var available: [String] = []
        var automatic: String?
        var networkReadings: [String: NetworkInterfaceReading] = [:]
        var details: [NetworkInterfaceInfo] = []
        if networkDemanded || configurationVisible {
            do {
                let counters = try readNetworkCounters()
                available = Array(Set(counters.map(\.name))).sorted()
                if configurationVisible || (detailVisible && settings.panels.contains { $0.isNetwork && $0.appearance.showsConnectionDetails }) {
                    let names = Set(counters.map(\.name))
                    if now - interfaceMetadataTimestamp >= 10 || names != metadataCounterNames {
                        interfaceMetadata = readMetadata(counters)
                        interfaceMetadataTimestamp = now
                        metadataCounterNames = names
                    }
                    details = interfaceMetadata
                    available = Array(Set(available).union(details.map(\.name))).sorted()
                }
                if now - networkMetadataTimestamp >= 10 {
                    physical = readPhysicalInterfaces()
                    networkMetadataTimestamp = now
                }
                // Route preference can change while both links stay up. Refresh
                // this small dynamic-store value each sample, not with inventory.
                // Configuration can resolve Auto without establishing rate state.
                primary = readPrimaryInterface()
                // Addresses change instantly (Wi-Fi off), unlike the cached physical inventory.
                let connected = primary.map(physical.contains) == true ? nil : readConnectedInterfaces()
                automatic = InterfaceSelection.select(counters, preferred: nil, primary: primary, physical: physical, connected: connected)?.name
                if networkDemanded {
                    var chosen: [String: InterfaceCounter] = [:]
                    for selection in selections {
                        if let counter = InterfaceSelection.select(counters, preferred: selection, primary: primary, physical: physical, connected: connected) {
                            chosen[counter.name] = counter
                        } else if let name = selection {
                            let missing = MetricReading(value: nil, detail: String(localized: "Interface \(name) unavailable"), timestamp: now)
                            networkReadings[name] = NetworkInterfaceReading(identity: "\(name):unavailable", name: name, download: missing, upload: missing)
                        }
                    }
                    let activeIDs = Set(chosen.values.map(\.identity))
                    networkRates = networkRates.filter { activeIDs.contains($0.key) }
                    // Auto and an explicit selection of the same device share
                    // one counter update and therefore the same measured rates.
                    for counter in chosen.values {
                        var tracker = networkRates[counter.identity] ?? InterfaceRateTracker()
                        let rate = tracker.update(identity: counter.identity, received: counter.received, sent: counter.sent, timestamp: now)
                        networkRates[counter.identity] = tracker
                        let detail = rate == nil ? String(localized: "Collecting \(counter.name) baseline") : String(localized: "\(counter.name) only; other interfaces excluded")
                        networkReadings[counter.name] = NetworkInterfaceReading(identity: counter.identity, name: counter.name,
                            download: MetricReading(value: rate?.download, detail: detail, timestamp: now),
                            upload: MetricReading(value: rate?.upload, detail: detail, timestamp: now))
                    }
                    // The legacy/global fields serve the optional readout. They
                    // never cause an extra interface baseline to be collected.
                    interface = settings.networkInterface ?? automatic ?? ""
                    for metric in [MetricID.download, .upload] where demanded.contains(metric) {
                        let selected = networkReadings[interface]
                        let reading = metric == .download ? selected?.download : selected?.upload
                        readings[metric] = reading ?? MetricReading(value: nil, detail: interface.isEmpty ? String(localized: "No active physical interface") : String(localized: "Interface \(interface) is not being sampled"), timestamp: now)
                    }
                } else {
                    // The settings picker needs inventory, not traffic samples or a baseline.
                    networkRates.removeAll()
                }
            } catch {
                // An unread interval cannot be treated as continuous traffic on recovery.
                networkRates.removeAll()
                for selection in selections {
                    if let name = selection {
                        let missing = unavailable(error, timestamp: now)
                        networkReadings[name] = NetworkInterfaceReading(identity: "\(name):unavailable", name: name, download: missing, upload: missing)
                    }
                }
                for metric in [MetricID.download, .upload] where demanded.contains(metric) {
                    readings[metric] = unavailable(error, timestamp: now)
                }
            }
        } else { networkRates.removeAll() }
        return Snapshot(timestamp: now, readings: readings, networkInterface: interface, availableInterfaces: available,
                        networkReadings: networkReadings, interfaceDetails: details, automaticNetworkInterface: automatic, cpuCores: cpuCores)
    }

    private func unavailable(_ error: Error, timestamp: TimeInterval) -> MetricReading {
        MetricReading(value: nil, detail: String(describing: error), timestamp: timestamp)
    }
}

enum MemoryAccounting {
    /// Used = active + wired + compressor physical pages. Inactive, free and
    /// speculative pages are excluded. This is occupancy, not memory pressure,
    /// and is not claimed to match Activity Monitor's accounting exactly.
    static func usedBytes(active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
        (active + wired + compressed) * pageSize
    }
}

enum NativeSystemReader {
    static func cpuTicks() throws -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw NativeReadError.system("CPU counters", result) }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                        idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    /// Per-logical-core tick buckets in the same user/system/idle/nice order
    /// as `host_cpu_load_info`. Callers own the returned baseline state.
    static func perCoreTicks() throws -> [CPUTicks] {
        var processorCount: natural_t = 0
        var loads: processor_info_array_t?
        var loadsCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &loads, &loadsCount)
        guard result == KERN_SUCCESS else { throw NativeReadError.system("Per-core CPU counters", result) }
        defer {
            if let base = loads {
                let size = vm_size_t(MemoryLayout<integer_t>.stride) * vm_size_t(loadsCount)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: base), size)
            }
        }
        guard let base = loads else { return [] }
        // processor_cpu_load_info is a four-integer cpu_ticks array per core:
        // user, system, idle, nice — the same order as host_cpu_load_info.
        let ticksPerCore = MemoryLayout<processor_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        let buffer = UnsafeBufferPointer(start: base, count: Int(loadsCount))
        return (0..<Int(processorCount)).map { core in
            let offset = core * ticksPerCore
            return CPUTicks(user: UInt64(buffer[offset]), system: UInt64(buffer[offset + 1]),
                            idle: UInt64(buffer[offset + 2]), nice: UInt64(buffer[offset + 3]))
        }
    }

    static func memory(timestamp: TimeInterval, units: CapacityUnits) throws -> MetricReading {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else { throw NativeReadError.system("VM page size", pageResult) }
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw NativeReadError.system("VM counters", result) }
        let used = MemoryAccounting.usedBytes(active: UInt64(info.active_count), inactive: UInt64(info.inactive_count),
                                               wired: UInt64(info.wire_count), compressed: UInt64(info.compressor_page_count), pageSize: UInt64(pageSize))
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { throw NativeReadError.system("Physical memory", EINVAL) }
        let usedText = DataSizePresentation.string(bytes: Double(min(used, total)), units: units)
        let totalText = DataSizePresentation.string(bytes: Double(total), units: units)
        return MetricReading(value: min(100, Double(used) / Double(total) * 100),
                             detail: String(localized: "\(usedText) used of \(totalText)"), timestamp: timestamp)
    }

    static func battery(timestamp: TimeInterval) -> MetricReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return MetricReading(value: nil, detail: String(localized: "Power source information unavailable"), timestamp: timestamp)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 else {
                return MetricReading(value: nil, detail: String(localized: "Battery capacity unavailable"), timestamp: timestamp)
            }
            let charging = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue == true
            let charged = (description[kIOPSIsChargedKey] as? NSNumber)?.boolValue == true
            let state = description[kIOPSPowerSourceStateKey] as? String
            // Line 1: state. Line 2: time and power. Line 3: health.
            var lines = [batteryState(charging: charging, charged: charged, state: state)]
            let smart = smartBatteryProperties()
            var power: [String] = []
            // kIOPSTimeToFullChargeKey / kIOPSTimeToEmptyKey are #defines, so
            // they stay raw strings here. -1 means the estimate is calculating.
            if charging {
                if let minutes = (description["Time to Full Charge"] as? NSNumber)?.doubleValue, minutes > 0 {
                    power.append(String(localized: "full in \(duration(minutes: minutes))"))
                }
            } else if !charged, state != kIOPSACPowerValue {
                // The per-source estimate is often absent; the system-wide one is not.
                let seconds = IOPSGetTimeRemainingEstimate()
                if let minutes = (description["Time to Empty"] as? NSNumber)?.doubleValue, minutes > 0 {
                    power.append(String(localized: "\(duration(minutes: minutes)) left", comment: "Battery time remaining"))
                } else if seconds > 0 {
                    power.append(String(localized: "\(duration(minutes: seconds / 60)) left", comment: "Battery time remaining"))
                } else {
                    power.append(String(localized: "estimating time left", comment: "Battery time remaining is being calculated"))
                }
                if let watts = smart.flatMap(drawWatts) { power.append(String(localized: "\(watts.formatted(.number.precision(.fractionLength(1)))) W draw", comment: "Battery power draw in watts")) }
            }
            if let watts = externalAdapterWatts(), state == kIOPSACPowerValue {
                power.append(String(localized: "\(Int(watts.rounded())) W adapter", comment: "Power adapter wattage"))
            }
            if !power.isEmpty { lines.append(power.joined(separator: " · ")) }
            var health: [String] = []
            // Some models nest the capacities in BatteryData.
            func capacity(_ key: String) -> Double? {
                ((smart?[key] ?? (smart?["BatteryData"] as? [String: Any])?[key]) as? NSNumber)?.doubleValue
            }
            if let raw = capacity("AppleRawMaxCapacity"), let design = capacity("DesignCapacity"), raw > 0, design > 0 {
                health.append(String(localized: "Health \(Int((min(1, raw / design) * 100).rounded()))%"))
            }
            if let cycles = (smart?["CycleCount"] as? NSNumber)?.intValue { health.append(String(localized: "\(cycles) cycles", comment: "Battery charge cycle count")) }
            if !health.isEmpty { lines.append(health.joined(separator: " · ")) }
            return MetricReading(value: min(100, max(0, current.doubleValue / maximum.doubleValue * 100)),
                                 detail: lines.joined(separator: "\n"), timestamp: timestamp)
        }
        return MetricReading(value: nil, detail: String(localized: "No internal battery"), timestamp: timestamp)
    }

    private static func batteryState(charging: Bool, charged: Bool, state: String?) -> String {
        if charging { return String(localized: "Charging") }
        if charged { return String(localized: "Charged") }
        return state == kIOPSACPowerValue ? String(localized: "Connected to power") : String(localized: "On battery")
    }

    /// Charger wattage via the public external-adapter dictionary; absent on
    /// desktop Macs or unsupported chargers, and simply omitted then.
    /// AppleSmartBattery registry properties (cycles, capacities, current);
    /// read in-process via IOKit, nil where the service does not exist.
    private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    /// Discharge power from signed current (mA, stored as unsigned 64-bit) and voltage (mV).
    private static func drawWatts(_ smart: [String: Any]) -> Double? {
        guard let amperage = smart["InstantAmperage"] as? NSNumber ?? smart["Amperage"] as? NSNumber,
              let voltage = (smart["Voltage"] as? NSNumber)?.doubleValue, voltage > 0 else { return nil }
        let milliamps = Double(Int64(bitPattern: amperage.uint64Value))
        guard milliamps < 0 else { return nil }
        return -milliamps * voltage / 1_000_000
    }

    private static func externalAdapterWatts() -> Double? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let number = details["Watts"] as? NSNumber, number.doubleValue > 0 else { return nil }
        return number.doubleValue
    }

    private static func duration(minutes: Double) -> String {
        let total = max(1, Int(minutes.rounded()))
        let hours = total / 60
        let minutesPart = total % 60
        if hours > 0 { return minutesPart == 0 ? String(localized: "\(hours) hr") : String(localized: "\(hours) hr \(minutesPart) min") }
        return String(localized: "\(minutesPart) min")
    }

    static func disk(timestamp: TimeInterval, units: CapacityUnits) throws -> MetricReading {
        let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values.volumeTotalCapacity, total > 0, let available = values.volumeAvailableCapacity else {
            throw NativeReadError.system("Root volume capacity", EINVAL)
        }
        // A single root-volume reading: total minus Foundation's available
        // capacity. APFS volumes share storage and must not be summed together.
        let used = total - min(total, max(0, available))
        let usedText = DataSizePresentation.string(bytes: Double(used), units: units)
        let totalText = DataSizePresentation.string(bytes: Double(total), units: units)
        let freeText = DataSizePresentation.string(bytes: Double(max(0, available)), units: units)
        return MetricReading(value: min(100, max(0, (1 - Double(available) / Double(total)) * 100)),
                             detail: String(localized: "Free: \(freeText)\n\(usedText) used of \(totalText)"), timestamp: timestamp)
    }

    static func thermal(timestamp: TimeInterval) -> MetricReading {
        let value: Double
        let detail: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: (value, detail) = (0, String(localized: "Nominal"))
        case .fair: (value, detail) = (1, String(localized: "Fair"))
        case .serious: (value, detail) = (2, String(localized: "Serious"))
        case .critical: (value, detail) = (3, String(localized: "Critical"))
        @unknown default: return MetricReading(value: nil, detail: String(localized: "Unknown system thermal state"), timestamp: timestamp)
        }
        return MetricReading(value: value, detail: detail, timestamp: timestamp)
    }
}
