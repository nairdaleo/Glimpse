import Foundation

public enum CounterRate: Sendable {
    /// A missing baseline or a reset needs a new baseline, never a zero or a spike.
    public static func bytesPerSecond(previous: UInt64?, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard let previous, current >= previous, elapsed.isFinite, elapsed > 0 else { return nil }
        let rate = Double(current - previous) / elapsed
        return rate.isFinite ? rate : nil
    }
}

public struct CPUTicks: Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUUsage: Sendable {
    public static func percentage(previous: CPUTicks?, current: CPUTicks) -> Double? {
        guard let previous,
              current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else { return nil }
        // Convert each delta before summing so a long-lived counter cannot overflow UInt64.
        let busy = Double(current.user - previous.user) + Double(current.system - previous.system) + Double(current.nice - previous.nice)
        let total = busy + Double(current.idle - previous.idle)
        guard total > 0 else { return nil }
        return min(100, max(0, busy / total * 100))
    }
}

public enum MetricPresentation: Sendable {
    public static func normalized(value: Double?, metric: MetricID, networkCeiling: Double) -> Double? {
        guard let value, value.isFinite else { return nil }
        let scale: Double
        switch metric {
        case .download, .upload:
            guard networkCeiling.isFinite, networkCeiling > 0 else { return nil }
            scale = networkCeiling
        case .thermal: scale = 3
        default: scale = 100
        }
        return min(1, max(0, value / scale))
    }

    public static func formatted(value: Double?, metric: MetricID, bits: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        switch metric {
        case .download, .upload:
            guard value >= 0 else { return "—" }
            let units = bits ? ["b/s", "Kb/s", "Mb/s", "Gb/s", "Tb/s", "Pb/s", "Eb/s"] : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s", "EB/s"]
            // Divide before converting bytes to bits to avoid overflow for finite inputs.
            var scaled = value
            var unit = 0
            while scaled >= 1_000 && unit < units.count - 1 {
                scaled /= 1_000
                unit += 1
            }
            if bits { scaled *= 8 }
            while scaled >= 999.5 && unit < units.count - 1 {
                scaled /= 1_000
                unit += 1
            }
            if scaled >= 999.5 { return ">999 \(units[unit])" }
            let decimals = unit > 0 && scaled < 100 ? 1 : 0
            return String(format: "%.*f %@", locale: Locale(identifier: "en_US_POSIX"), decimals, scaled, units[unit])
        case .thermal:
            guard value >= 0, value <= 3, value.rounded() == value else { return "—" }
            return ["Nominal", "Fair", "Serious", "Critical"][Int(value)]
        default:
            return String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), min(100, max(0, value)))
        }
    }
}

/// Human-readable byte counts for capacity readings, using SI (1000-based,
/// GB) or IEC (1024-based, GiB) prefixes.
public enum DataSizePresentation: Sendable {
    public static func string(bytes: Double, units: CapacityUnits) -> String {
        guard bytes.isFinite else { return "—" }
        let step = units == .si ? 1000.0 : 1024.0
        let suffixes = units == .si ? ["B", "KB", "MB", "GB", "TB", "PB"] : ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var scaled = max(0, bytes)
        var unit = 0
        while scaled >= step && unit < suffixes.count - 1 {
            scaled /= step
            unit += 1
        }
        let decimals = scaled >= 100 ? 0 : (scaled >= 10 ? 1 : 2)
        return String(format: "%.*f %@", locale: Locale(identifier: "en_US_POSIX"), decimals, scaled, suffixes[unit])
    }
}
