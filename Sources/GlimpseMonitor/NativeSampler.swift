import Foundation
import Darwin
import IOKit.ps
import GlimpseCore

/// Mutable sampling state belongs to the application's single sampling queue.
/// This class intentionally has no internal timer and must not be called concurrently.
public final class NativeSampler {
    private var cpuBaseline: CPUTicks?
    private var networkRates: [String: InterfaceRateTracker] = [:]
    private var cache: [MetricID: MetricReading] = [:]
    private var physical: Set<String> = []
    private var primary: String?
    private var networkMetadataTimestamp: TimeInterval = -.infinity
    private var interfaceMetadata: [NetworkInterfaceInfo] = []
    private var interfaceMetadataTimestamp: TimeInterval = -.infinity
    private var metadataCounterNames: Set<String> = []
    private let readNetworkCounters: () throws -> [InterfaceCounter]
    private let clock: () -> TimeInterval
    private let readPhysicalInterfaces: () -> Set<String>
    private let readPrimaryInterface: () -> String?
    private let readMetadata: ([InterfaceCounter]) -> [NetworkInterfaceInfo]

    public convenience init() { self.init(networkReader: NativeNetworkReader.readCounters) }

    internal init(networkReader: @escaping () throws -> [InterfaceCounter],
                  clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                  physicalReader: @escaping () -> Set<String> = NativeNetworkReader.physicalInterfaces,
                  primaryReader: @escaping () -> String? = NativeNetworkReader.primaryInterface,
                  metadataReader: @escaping ([InterfaceCounter]) -> [NetworkInterfaceInfo] = NativeNetworkMetadata.read) {
        readNetworkCounters = networkReader
        self.clock = clock
        readPhysicalInterfaces = physicalReader
        readPrimaryInterface = primaryReader
        readMetadata = metadataReader
    }

    public func resetBaselines() {
        cpuBaseline = nil
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
        if demanded.contains(.cpu) {
            do {
                let ticks = try NativeSystemReader.cpuTicks()
                let value = CPUUsage.percentage(previous: cpuBaseline, current: ticks)
                cpuBaseline = ticks
                readings[.cpu] = MetricReading(value: value, detail: value == nil ? "Collecting CPU baseline" : "CPU activity across all cores", timestamp: now)
            } catch {
                cpuBaseline = nil
                readings[.cpu] = unavailable(error, timestamp: now)
            }
        } else { cpuBaseline = nil }

        for (metric, interval) in [(MetricID.memory, 2.0), (.battery, 10), (.disk, 30), (.thermal, 5)] where demanded.contains(metric) {
            if let previous = cache[metric], now - previous.timestamp < interval {
                readings[metric] = previous
                continue
            }
            let reading: MetricReading
            do {
                switch metric {
                case .memory: reading = try NativeSystemReader.memory(timestamp: now)
                case .battery: reading = NativeSystemReader.battery(timestamp: now)
                case .disk: reading = try NativeSystemReader.disk(timestamp: now)
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
                if configurationVisible || detailVisible {
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
                automatic = InterfaceSelection.select(counters, preferred: nil, primary: primary, physical: physical)?.name
                if networkDemanded {
                    var chosen: [String: InterfaceCounter] = [:]
                    for selection in selections {
                        if let counter = InterfaceSelection.select(counters, preferred: selection, primary: primary, physical: physical) {
                            chosen[counter.name] = counter
                        } else if let name = selection {
                            let missing = MetricReading(value: nil, detail: "Interface \(name) unavailable", timestamp: now)
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
                        let detail = rate == nil ? "Collecting \(counter.name) baseline" : "\(counter.name) only; other interfaces excluded"
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
                        readings[metric] = reading ?? MetricReading(value: nil, detail: interface.isEmpty ? "No active physical interface" : "Interface \(interface) is not being sampled", timestamp: now)
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
                        networkReadings: networkReadings, interfaceDetails: details, automaticNetworkInterface: automatic)
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

    static func memory(timestamp: TimeInterval) throws -> MetricReading {
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
        let usedText = ByteCountFormatter.string(fromByteCount: Int64(clamping: min(used, total)), countStyle: .memory)
        let totalText = ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .memory)
        return MetricReading(value: min(100, Double(used) / Double(total) * 100),
                             detail: "\(usedText) used of \(totalText) · Usage, not memory pressure", timestamp: timestamp)
    }

    static func battery(timestamp: TimeInterval) -> MetricReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return MetricReading(value: nil, detail: "Power source information unavailable", timestamp: timestamp)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            guard let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
                  let maximum = description[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 else {
                return MetricReading(value: nil, detail: "Battery capacity unavailable", timestamp: timestamp)
            }
            let charging = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue == true
            let state = description[kIOPSPowerSourceStateKey] as? String
            let detail = charging ? "Charging" : (state == kIOPSACPowerValue ? "Connected to power" : "On battery")
            return MetricReading(value: min(100, max(0, current.doubleValue / maximum.doubleValue * 100)), detail: detail, timestamp: timestamp)
        }
        return MetricReading(value: nil, detail: "No internal battery", timestamp: timestamp)
    }

    static func disk(timestamp: TimeInterval) throws -> MetricReading {
        let values = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        guard let total = values.volumeTotalCapacity, total > 0, let available = values.volumeAvailableCapacity else {
            throw NativeReadError.system("Root volume capacity", EINVAL)
        }
        // A single root-volume reading: total minus Foundation's available
        // capacity. APFS volumes share storage and must not be summed together.
        let used = total - min(total, max(0, available))
        let usedText = ByteCountFormatter.string(fromByteCount: Int64(clamping: used), countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file)
        return MetricReading(value: min(100, max(0, (1 - Double(available) / Double(total)) * 100)),
                             detail: "/ · \(usedText) used of \(totalText)", timestamp: timestamp)
    }

    static func thermal(timestamp: TimeInterval) -> MetricReading {
        let value: Double
        let detail: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: (value, detail) = (0, "Nominal")
        case .fair: (value, detail) = (1, "Fair")
        case .serious: (value, detail) = (2, "Serious")
        case .critical: (value, detail) = (3, "Critical")
        @unknown default: return MetricReading(value: nil, detail: "Unknown system thermal state", timestamp: timestamp)
        }
        return MetricReading(value: value, detail: detail, timestamp: timestamp)
    }
}
