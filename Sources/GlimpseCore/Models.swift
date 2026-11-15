import Foundation

public enum MetricID: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, download, upload, battery, disk, thermal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return String(localized: "Memory")
        case .download: return String(localized: "Download")
        case .upload: return String(localized: "Upload")
        case .battery: return String(localized: "Battery")
        case .disk: return String(localized: "Disk")
        case .thermal: return String(localized: "Thermal")
        }
    }
}

public struct MetricReading: Sendable {
    public var value: Double?
    public var detail: String
    public var timestamp: TimeInterval
    public init(value: Double?, detail: String, timestamp: TimeInterval) {
        self.value = value
        self.detail = detail
        self.timestamp = timestamp
    }
}

public struct Snapshot: Sendable {
    public var timestamp: TimeInterval
    public var readings: [MetricID: MetricReading]
    public var networkInterface: String
    public var availableInterfaces: [String]
    public var networkReadings: [String: NetworkInterfaceReading]
    public var interfaceDetails: [NetworkInterfaceInfo]
    public var automaticNetworkInterface: String?
    /// Utilization percentage per logical CPU core, in core order.
    /// Empty until the first per-core baseline exists.
    public var cpuCores: [Double]
    public init(timestamp: TimeInterval, readings: [MetricID: MetricReading] = [:], networkInterface: String = "", availableInterfaces: [String] = [],
                networkReadings: [String: NetworkInterfaceReading] = [:], interfaceDetails: [NetworkInterfaceInfo] = [], automaticNetworkInterface: String? = nil,
                cpuCores: [Double] = []) {
        self.timestamp = timestamp
        self.readings = readings
        self.networkInterface = networkInterface
        self.availableInterfaces = availableInterfaces
        self.networkReadings = networkReadings
        self.interfaceDetails = interfaceDetails
        self.automaticNetworkInterface = automaticNetworkInterface
        self.cpuCores = cpuCores
    }

    public func networkReading(for metric: MetricID, interface: String?) -> MetricReading? {
        guard let name = interface ?? automaticNetworkInterface, let reading = networkReadings[name] else { return nil }
        switch metric {
        case .download: return reading.download
        case .upload: return reading.upload
        default: return nil
        }
    }

    public func networkInfo(for interface: String?) -> NetworkInterfaceInfo? {
        guard let name = interface ?? automaticNetworkInterface else { return nil }
        return interfaceDetails.first { $0.name == name }
    }
}

public enum MeterColour: RawRepresentable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case mint, green, blue, purple, orange, pink
    case custom(RGB)

    public struct RGB: Hashable, Codable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            func component(_ value: Double) -> Double {
                guard value.isFinite, value > 0 else { return 0 }
                return min(1, value)
            }
            self.red = component(red)
            self.green = component(green)
            self.blue = component(blue)
        }

        private enum CodingKeys: String, CodingKey { case red, green, blue }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(red: try values.decode(Double.self, forKey: .red),
                      green: try values.decode(Double.self, forKey: .green),
                      blue: try values.decode(Double.self, forKey: .blue))
        }
    }

    // Custom colours remain available through the native picker; these are suggestions.
    public static let allCases: [MeterColour] = [.mint, .green, .blue, .purple, .orange, .pink]
    public static func custom(red: Double, green: Double, blue: Double) -> MeterColour {
        .custom(RGB(red: red, green: green, blue: blue))
    }

    public var rawValue: String {
        switch self {
        case .mint: return "mint"
        case .green: return "green"
        case .blue: return "blue"
        case .purple: return "purple"
        case .orange: return "orange"
        case .pink: return "pink"
        case .custom(let rgb): return "custom:\(rgb.red),\(rgb.green),\(rgb.blue)"
        }
    }
    public init?(rawValue: String) {
        switch rawValue {
        case "mint": self = .mint
        case "green": self = .green
        case "blue": self = .blue
        case "purple": self = .purple
        case "orange": self = .orange
        case "pink": self = .pink
        default:
            guard rawValue.hasPrefix("custom:") else { return nil }
            let parts = rawValue.dropFirst(7).split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 3, let red = Double(parts[0]), let green = Double(parts[1]),
                  let blue = Double(parts[2]), red.isFinite, green.isFinite, blue.isFinite else { return nil }
            self = .custom(red: red, green: green, blue: blue)
        }
    }
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mint: return String(localized: "Mint")
        case .green: return String(localized: "Green")
        case .blue: return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .orange: return String(localized: "Orange")
        case .pink: return String(localized: "Pink")
        case .custom: return String(localized: "Custom")
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let name = try? value.decode(String.self) {
            guard let colour = Self(rawValue: name) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown meter colour")
            }
            self = colour
        } else {
            self = .custom(try RGB(from: decoder))
        }
    }
    public func encode(to encoder: Encoder) throws {
        if case .custom(let rgb) = self {
            try rgb.encode(to: encoder)
        } else {
            var value = encoder.singleValueContainer()
            try value.encode(rawValue)
        }
    }
}

public enum ThresholdDirection: String, Codable, CaseIterable, Sendable {
    case above, below
}

public struct HistoryPoint: Sendable {
    public var timestamp: TimeInterval
    public var value: Double?
    public init(timestamp: TimeInterval, value: Double?) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// Level-based colouring with one to three colours. The meter's own colour
/// is colour 1 (lowest); each stop switches to its colour at or above its
/// threshold (0...100). With `gradient`, colours blend between anchors at 0%
/// and each threshold instead of changing hard.
public struct ColourBands: Codable, Equatable, Sendable {
    public struct Stop: Codable, Equatable, Sendable {
        public var threshold: Double
        public var colour: MeterColour
        public init(threshold: Double, colour: MeterColour) { self.threshold = threshold; self.colour = colour }
    }

    public var stops: [Stop]
    public var gradient: Bool

    public static let yellow = MeterColour.custom(red: 1.00, green: 0.80, blue: 0.00)

    public init(stops: [Stop] = [], gradient: Bool = false) {
        self.stops = stops
        self.gradient = gradient
    }

    /// Default stops for a total of `count` colours (2 or 3).
    public static func defaults(count: Int) -> [Stop] {
        count >= 3 ? [Stop(threshold: 20, colour: yellow), Stop(threshold: 50, colour: .green)] : [Stop(threshold: 20, colour: .green)]
    }

    /// At most two stops, thresholds clamped to 0...100 and ascending.
    public func validated() -> ColourBands {
        var result = self
        result.stops = Array(stops.prefix(2)).map {
            Stop(threshold: $0.threshold.isFinite ? min(100, max(0, $0.threshold)) : 50, colour: $0.colour)
        }.sorted { $0.threshold < $1.threshold }
        return result
    }

    /// The colour for `value`: blend `from` towards `to` by `fraction`.
    public func colour(for value: Double, base: MeterColour) -> (from: MeterColour, to: MeterColour, fraction: Double) {
        let anchors = [(0.0, base)] + stops.map { ($0.threshold, $0.colour) }
        guard gradient else {
            let colour = anchors.last { value >= $0.0 }?.1 ?? base
            return (colour, colour, 0)
        }
        for (a, b) in zip(anchors, anchors.dropFirst()) where value < b.0 {
            let span = b.0 - a.0
            return (a.1, b.1, span > 0 ? max(0, (value - a.0) / span) : 1)
        }
        let last = anchors[anchors.count - 1].1
        return (last, last, 0)
    }
}
