import Foundation

public enum MetricID: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, download, upload, battery, disk, thermal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .download: return "Download"
        case .upload: return "Upload"
        case .battery: return "Battery"
        case .disk: return "Disk"
        case .thermal: return "Thermal"
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
    case mint, blue, purple, orange, pink
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
    public static let allCases: [MeterColour] = [.mint, .blue, .purple, .orange, .pink]
    public static func custom(red: Double, green: Double, blue: Double) -> MeterColour {
        .custom(RGB(red: red, green: green, blue: blue))
    }

    public var rawValue: String {
        switch self {
        case .mint: return "mint"
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
        if case .custom = self { return "Custom" }
        return rawValue.capitalized
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

/// Level-based colouring: value >= highThreshold uses `high`, value <=
/// lowThreshold uses `low`, anything between uses `middle`. A nil band uses
/// the meter's own colour, so one, two or three colours can be chosen.
public struct ColourBands: Codable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable { case hard, gradient }

    public var style: Style
    public var high: MeterColour?
    public var middle: MeterColour?
    public var low: MeterColour?
    public var highThreshold: Double
    public var lowThreshold: Double

    public static let green = MeterColour.custom(red: 0.20, green: 0.78, blue: 0.35)
    public static let yellow = MeterColour.custom(red: 1.00, green: 0.80, blue: 0.00)
    public static let red = MeterColour.custom(red: 1.00, green: 0.23, blue: 0.19)

    public init(style: Style = .hard, high: MeterColour? = ColourBands.green, middle: MeterColour? = ColourBands.yellow,
                low: MeterColour? = ColourBands.red, highThreshold: Double = 50, lowThreshold: Double = 20) {
        self.style = style
        self.high = high
        self.middle = middle
        self.low = low
        self.highThreshold = highThreshold
        self.lowThreshold = lowThreshold
    }

    /// Thresholds clamped to 0...100 with low <= high.
    public func validated() -> ColourBands {
        var result = self
        func clamp(_ value: Double, _ fallback: Double) -> Double { value.isFinite ? min(100, max(0, value)) : fallback }
        let high = clamp(highThreshold, 50), low = clamp(lowThreshold, 20)
        result.highThreshold = max(high, low)
        result.lowThreshold = min(high, low)
        return result
    }

    /// The colour for `value`: blend `from` towards `to` by `fraction`
    /// (0 for a hard change). Missing bands resolve to `base`.
    public func colour(for value: Double, base: MeterColour) -> (from: MeterColour, to: MeterColour, fraction: Double) {
        let high = self.high ?? base, middle = self.middle ?? base, low = self.low ?? base
        switch style {
        case .hard:
            if value >= highThreshold { return (high, high, 0) }
            if value <= lowThreshold { return (low, low, 0) }
            return (middle, middle, 0)
        case .gradient:
            // Anchors: low at lowThreshold, middle (if chosen) halfway, high at highThreshold.
            var anchors = [(lowThreshold, low)]
            if self.middle != nil { anchors.append(((lowThreshold + highThreshold) / 2, middle)) }
            anchors.append((highThreshold, high))
            if value <= anchors[0].0 { return (low, low, 0) }
            for (a, b) in zip(anchors, anchors.dropFirst()) where value <= b.0 {
                let span = b.0 - a.0
                return (a.1, b.1, span > 0 ? (value - a.0) / span : 1)
            }
            return (high, high, 0)
        }
    }
}
