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
    public init(timestamp: TimeInterval, readings: [MetricID: MetricReading] = [:], networkInterface: String = "", availableInterfaces: [String] = []) {
        self.timestamp = timestamp
        self.readings = readings
        self.networkInterface = networkInterface
        self.availableInterfaces = availableInterfaces
    }
}

public enum MeterColour: String, Codable, CaseIterable, Identifiable, Sendable {
    case mint, blue, purple, orange, pink
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
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
