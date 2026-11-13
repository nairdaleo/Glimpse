import Foundation

public struct ColumnConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var metric: MetricID
    public var colour: MeterColour
    public var warningThreshold: Double?
    public var criticalThreshold: Double?
    public var thresholdDirection: ThresholdDirection

    public init(metric: MetricID, colour: MeterColour, warningThreshold: Double? = nil, criticalThreshold: Double? = nil, thresholdDirection: ThresholdDirection = .above, id: UUID = UUID()) {
        self.id = id
        self.metric = metric
        self.colour = colour
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.thresholdDirection = thresholdDirection
    }

    private enum CodingKeys: String, CodingKey { case id, metric, colour, warningThreshold, criticalThreshold, thresholdDirection }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(UUID.self, forKey: .id)) ?? UUID()
        metric = (try? values.decode(MetricID.self, forKey: .metric)) ?? .cpu
        colour = (try? values.decode(MeterColour.self, forKey: .colour)) ?? .mint
        warningThreshold = try? values.decode(Double.self, forKey: .warningThreshold)
        criticalThreshold = try? values.decode(Double.self, forKey: .criticalThreshold)
        thresholdDirection = (try? values.decode(ThresholdDirection.self, forKey: .thresholdDirection)) ?? .above
    }

    fileprivate func validated() -> ColumnConfiguration {
        var result = self
        let maximum: Double = metric == .thermal ? 3 : (metric == .download || metric == .upload ? .greatestFiniteMagnitude : 100)
        func valid(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return min(value, maximum)
        }
        result.warningThreshold = valid(warningThreshold)
        result.criticalThreshold = valid(criticalThreshold)
        if let warning = result.warningThreshold, let critical = result.criticalThreshold,
           (thresholdDirection == .above && warning > critical) || (thresholdDirection == .below && warning < critical) {
            result.warningThreshold = critical
            result.criticalThreshold = warning
        }
        return result
    }
}

public struct AppSettings: Codable, Sendable {
    public var columns: [ColumnConfiguration]
    public var columnScale: Double
    public var panelMetrics: [MetricID]
    public var showBandwidth: Bool
    public var bandwidthInBits: Bool
    public var networkInterface: String?
    public var networkCeiling: Double
    public var refreshInterval: Double
    public var monochrome: Bool

    public init() {
        columns = [ColumnConfiguration(metric: .cpu, colour: .mint), ColumnConfiguration(metric: .memory, colour: .purple), ColumnConfiguration(metric: .download, colour: .blue)]
        columnScale = 1
        panelMetrics = MetricID.allCases
        showBandwidth = false
        bandwidthInBits = false
        networkInterface = nil
        networkCeiling = 12_500_000
        refreshInterval = 1
        monochrome = false
    }

    private enum CodingKeys: String, CodingKey { case columns, columnScale, panelMetrics, showBandwidth, bandwidthInBits, networkInterface, networkCeiling, refreshInterval, monochrome }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        columns = (try? values.decode([ColumnConfiguration].self, forKey: .columns)) ?? columns
        columnScale = (try? values.decode(Double.self, forKey: .columnScale)) ?? columnScale
        if let rawPanels = try? values.decode([String].self, forKey: .panelMetrics) {
            panelMetrics = rawPanels.compactMap(MetricID.init(rawValue:))
        }
        showBandwidth = (try? values.decode(Bool.self, forKey: .showBandwidth)) ?? showBandwidth
        bandwidthInBits = (try? values.decode(Bool.self, forKey: .bandwidthInBits)) ?? bandwidthInBits
        networkInterface = try? values.decode(String.self, forKey: .networkInterface)
        networkCeiling = (try? values.decode(Double.self, forKey: .networkCeiling)) ?? networkCeiling
        refreshInterval = (try? values.decode(Double.self, forKey: .refreshInterval)) ?? refreshInterval
        monochrome = (try? values.decode(Bool.self, forKey: .monochrome)) ?? monochrome
        self = validated()
    }

    public func validated() -> AppSettings {
        var result = self
        let defaults = AppSettings()
        result.columns = Array(columns.prefix(8)).map { $0.validated() }
        if result.columns.isEmpty { result.columns = [defaults.columns[0]] }
        var columnIDs: Set<UUID> = []
        for index in result.columns.indices {
            while !columnIDs.insert(result.columns[index].id).inserted {
                result.columns[index].id = UUID()
            }
        }
        result.columnScale = columnScale.isFinite ? min(1.5, max(0.75, columnScale)) : 1
        var panels: Set<MetricID> = []
        result.panelMetrics = panelMetrics.filter { panels.insert($0).inserted }
        if !networkCeiling.isFinite || networkCeiling <= 0 { result.networkCeiling = defaults.networkCeiling }
        result.refreshInterval = refreshInterval.isFinite ? min(60, max(1, refreshInterval)) : defaults.refreshInterval
        let interface = networkInterface?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.networkInterface = interface?.isEmpty == false ? interface : nil
        return result
    }
}
