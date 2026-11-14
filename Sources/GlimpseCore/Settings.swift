import Foundation

public struct ColumnConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var metric: MetricID
    public var colour: MeterColour
    public var isCombinedNetwork: Bool
    public var secondaryColour: MeterColour
    public var networkInterface: String?
    public var warningThreshold: Double?
    public var criticalThreshold: Double?
    public var thresholdDirection: ThresholdDirection

    public init(metric: MetricID, colour: MeterColour, warningThreshold: Double? = nil, criticalThreshold: Double? = nil, thresholdDirection: ThresholdDirection = .above, id: UUID = UUID(), isCombinedNetwork: Bool = false, secondaryColour: MeterColour = .blue, networkInterface: String? = nil) {
        self.id = id
        self.metric = metric
        self.colour = colour
        self.isCombinedNetwork = isCombinedNetwork
        self.secondaryColour = secondaryColour
        self.networkInterface = networkInterface
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.thresholdDirection = thresholdDirection
    }

    public var displayTitle: String { isCombinedNetwork ? "Upload / Download" : metric.title }
    public var requiredMetrics: [MetricID] { isCombinedNetwork ? [.upload, .download] : [metric] }
    public var isNetwork: Bool { isCombinedNetwork || metric == .upload || metric == .download }

    private enum CodingKeys: String, CodingKey { case id, metric, colour, warningThreshold, criticalThreshold, thresholdDirection, isCombinedNetwork, secondaryColour, networkInterface }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(UUID.self, forKey: .id)) ?? UUID()
        metric = (try? values.decode(MetricID.self, forKey: .metric)) ?? .cpu
        colour = (try? values.decode(MeterColour.self, forKey: .colour)) ?? .mint
        isCombinedNetwork = (try? values.decode(Bool.self, forKey: .isCombinedNetwork)) ?? false
        secondaryColour = (try? values.decode(MeterColour.self, forKey: .secondaryColour)) ?? .blue
        networkInterface = try? values.decode(String.self, forKey: .networkInterface)
        warningThreshold = try? values.decode(Double.self, forKey: .warningThreshold)
        criticalThreshold = try? values.decode(Double.self, forKey: .criticalThreshold)
        thresholdDirection = (try? values.decode(ThresholdDirection.self, forKey: .thresholdDirection)) ?? .above
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(metric, forKey: .metric)
        try values.encode(colour, forKey: .colour)
        try values.encode(isCombinedNetwork, forKey: .isCombinedNetwork)
        try values.encode(secondaryColour, forKey: .secondaryColour)
        // Null is explicit Auto; omission is reserved for pre-interface settings migration.
        try values.encode(networkInterface, forKey: .networkInterface)
        try values.encodeIfPresent(warningThreshold, forKey: .warningThreshold)
        try values.encodeIfPresent(criticalThreshold, forKey: .criticalThreshold)
        try values.encode(thresholdDirection, forKey: .thresholdDirection)
    }

    fileprivate func validated() -> ColumnConfiguration {
        var result = self
        if isCombinedNetwork { result.metric = .download }
        result.networkInterface = isNetwork ? cleanedInterface(networkInterface) : nil
        let maximum: Double = result.metric == .thermal ? 3 : (result.metric == .download || result.metric == .upload ? .greatestFiniteMagnitude : 100)
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

private func cleanedInterface(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
}

private struct ColumnInterfacePresence: Decodable {
    let isExplicit: Bool
    private enum CodingKeys: String, CodingKey { case networkInterface }
    init(from decoder: Decoder) throws {
        isExplicit = try decoder.container(keyedBy: CodingKeys.self).contains(.networkInterface)
    }
}

public enum PanelCardSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact, regular, large
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Byte-count presentation for capacity readings: SI powers of 1000 (GB) or
/// IEC powers of 1024 (GiB).
public enum CapacityUnits: String, Codable, CaseIterable, Identifiable, Sendable {
    case si, iec
    public var id: String { rawValue }
    public var title: String { self == .si ? "SI (GB)" : "IEC (GiB)" }
}

public enum PanelLargeOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case vertical, horizontal
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .vertical: return "1 × 2 · Vertical"
        case .horizontal: return "2 × 1 · Horizontal"
        }
    }
}

public struct PanelAppearance: Codable, Equatable, Sendable {
    public var size: PanelCardSize
    public var colour: MeterColour
    public var showsHistory: Bool
    public var largeOrientation: PanelLargeOrientation
    public var showsConnectionDetails: Bool

    public init(size: PanelCardSize = .regular, colour: MeterColour = .blue, showsHistory: Bool = true, largeOrientation: PanelLargeOrientation = .vertical, showsConnectionDetails: Bool = false) {
        self.size = size
        self.colour = colour
        self.showsHistory = showsHistory
        self.largeOrientation = largeOrientation
        self.showsConnectionDetails = showsConnectionDetails
    }

    private enum CodingKeys: String, CodingKey { case size, colour, showsHistory, largeOrientation, showsConnectionDetails }
    public init(from decoder: Decoder) throws {
        self.init()
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        size = (try? values.decode(PanelCardSize.self, forKey: .size)) ?? size
        colour = (try? values.decode(MeterColour.self, forKey: .colour)) ?? colour
        showsHistory = (try? values.decode(Bool.self, forKey: .showsHistory)) ?? showsHistory
        largeOrientation = (try? values.decode(PanelLargeOrientation.self, forKey: .largeOrientation)) ?? largeOrientation
        showsConnectionDetails = (try? values.decode(Bool.self, forKey: .showsConnectionDetails)) ?? showsConnectionDetails
    }
}

public struct PanelConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var metric: MetricID
    public var isCombinedNetwork: Bool
    public var networkInterface: String?
    public var appearance: PanelAppearance

    public init(metric: MetricID, id: UUID = UUID(), isCombinedNetwork: Bool = false, networkInterface: String? = nil, appearance: PanelAppearance = PanelAppearance()) {
        self.id = id
        self.metric = metric
        self.isCombinedNetwork = isCombinedNetwork
        self.networkInterface = networkInterface
        self.appearance = appearance
    }

    public var displayTitle: String { isCombinedNetwork ? "Upload / Download" : metric.title }
    public var requiredMetrics: [MetricID] { isCombinedNetwork ? [.upload, .download] : [metric] }
    public var isNetwork: Bool { isCombinedNetwork || metric == .upload || metric == .download }

    private enum CodingKeys: String, CodingKey { case id, metric, isCombinedNetwork, networkInterface, appearance }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? values.decode(UUID.self, forKey: .id)) ?? UUID()
        metric = (try? values.decode(MetricID.self, forKey: .metric)) ?? .cpu
        isCombinedNetwork = (try? values.decode(Bool.self, forKey: .isCombinedNetwork)) ?? false
        networkInterface = try? values.decode(String.self, forKey: .networkInterface)
        appearance = (try? values.decode(PanelAppearance.self, forKey: .appearance)) ?? PanelAppearance()
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(metric, forKey: .metric)
        try values.encode(isCombinedNetwork, forKey: .isCombinedNetwork)
        try values.encode(networkInterface, forKey: .networkInterface)
        try values.encode(appearance, forKey: .appearance)
    }
    fileprivate func validated() -> PanelConfiguration {
        var result = self
        if isCombinedNetwork { result.metric = .download }
        result.networkInterface = isNetwork ? cleanedInterface(networkInterface) : nil
        return result
    }
}

public struct AppSettings: Codable, Sendable {
    public var columns: [ColumnConfiguration]
    public var columnScale: Double
    public var panels: [PanelConfiguration]
    public var panelColumns: Int
    public var panelCardWidth: Double
    private var legacyPanelAppearances: [String: PanelAppearance]
    public var showBandwidth: Bool
    public var bandwidthInBits: Bool
    public var networkInterface: String?
    /// Download full-scale rate in bytes/second (the legacy single ceiling).
    public var networkCeiling: Double
    /// Upload full-scale rate in bytes/second; plans are often asymmetric.
    public var uploadCeiling: Double
    public var refreshInterval: Double
    public var monochrome: Bool
    /// Byte-count presentation for memory and disk readings.
    public var capacityUnits: CapacityUnits
    /// Prefix base for upload/download rates and the network ceiling.
    public var bandwidthUnits: CapacityUnits

    public init() {
        columns = [ColumnConfiguration(metric: .cpu, colour: .mint), ColumnConfiguration(metric: .memory, colour: .purple), ColumnConfiguration(metric: .download, colour: .blue)]
        columnScale = 1
        panels = MetricID.allCases.map { PanelConfiguration(metric: $0) }
        panelColumns = 2
        panelCardWidth = 156
        legacyPanelAppearances = [:]
        showBandwidth = false
        bandwidthInBits = false
        networkInterface = nil
        networkCeiling = 12_500_000
        uploadCeiling = 12_500_000
        refreshInterval = 1
        monochrome = false
        capacityUnits = .si
        bandwidthUnits = .si
    }

    /// Compatibility projections for callers that still organize one card per metric.
    /// Identity-aware callers use panels directly and may keep repeated network metrics.
    public var panelMetrics: [MetricID] {
        get {
            var seen: Set<MetricID> = []
            return panels.map(\.metric).filter { seen.insert($0).inserted }
        }
        set {
            let appearances = panelAppearances
            var seen: Set<MetricID> = []
            let previous = panels
            let next = newValue.filter { seen.insert($0).inserted }.map { metric in
                previous.first { $0.metric == metric } ?? PanelConfiguration(metric: metric, networkInterface: metric == .upload || metric == .download ? networkInterface : nil, appearance: appearances[metric.rawValue] ?? PanelAppearance())
            }
            panels = next
            legacyPanelAppearances = appearances
        }
    }
    public var panelAppearances: [String: PanelAppearance] {
        get {
            var result = legacyPanelAppearances
            var seen: Set<MetricID> = []
            for panel in panels where seen.insert(panel.metric).inserted {
                if panel.appearance != PanelAppearance() || result[panel.metric.rawValue] != nil {
                    result[panel.metric.rawValue] = panel.appearance
                }
            }
            return result
        }
        set {
            legacyPanelAppearances = newValue
            for index in panels.indices {
                panels[index].appearance = newValue[panels[index].metric.rawValue] ?? PanelAppearance()
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case columns, columnScale, panels, panelMetrics, panelColumns, panelCardWidth, panelAppearances, showBandwidth, bandwidthInBits, networkInterface, networkCeiling, uploadCeiling, refreshInterval, monochrome, capacityUnits, bandwidthUnits }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        networkInterface = try? values.decode(String.self, forKey: .networkInterface)
        columns = (try? values.decode([ColumnConfiguration].self, forKey: .columns)) ?? columns
        let presence = (try? values.decode([ColumnInterfacePresence].self, forKey: .columns)) ?? []
        for index in columns.indices where columns[index].isNetwork && (index >= presence.count || !presence[index].isExplicit) {
            columns[index].networkInterface = networkInterface
        }
        columnScale = (try? values.decode(Double.self, forKey: .columnScale)) ?? columnScale
        legacyPanelAppearances = (try? values.decode([String: PanelAppearance].self, forKey: .panelAppearances)) ?? [:]
        if let decodedPanels = try? values.decode([PanelConfiguration].self, forKey: .panels) {
            panels = decodedPanels
        } else {
            let rawPanels = (try? values.decode([String].self, forKey: .panelMetrics)) ?? MetricID.allCases.map(\.rawValue)
            panels = MetricID.allCases.map { metric in
                PanelConfiguration(metric: metric, networkInterface: metric == .upload || metric == .download ? networkInterface : nil, appearance: legacyPanelAppearances[metric.rawValue] ?? PanelAppearance())
            }
            panelMetrics = rawPanels.compactMap(MetricID.init(rawValue:))
        }
        panelColumns = (try? values.decode(Int.self, forKey: .panelColumns)) ?? panelColumns
        panelCardWidth = (try? values.decode(Double.self, forKey: .panelCardWidth)) ?? panelCardWidth
        showBandwidth = (try? values.decode(Bool.self, forKey: .showBandwidth)) ?? showBandwidth
        bandwidthInBits = (try? values.decode(Bool.self, forKey: .bandwidthInBits)) ?? bandwidthInBits
        networkCeiling = (try? values.decode(Double.self, forKey: .networkCeiling)) ?? networkCeiling
        // Legacy settings had one shared ceiling; upload starts from it.
        uploadCeiling = (try? values.decode(Double.self, forKey: .uploadCeiling)) ?? networkCeiling
        refreshInterval = (try? values.decode(Double.self, forKey: .refreshInterval)) ?? refreshInterval
        monochrome = (try? values.decode(Bool.self, forKey: .monochrome)) ?? monochrome
        capacityUnits = (try? values.decode(CapacityUnits.self, forKey: .capacityUnits)) ?? capacityUnits
        bandwidthUnits = (try? values.decode(CapacityUnits.self, forKey: .bandwidthUnits)) ?? bandwidthUnits
        self = validated()
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(columns, forKey: .columns)
        try values.encode(columnScale, forKey: .columnScale)
        try values.encode(panels, forKey: .panels)
        // Retain legacy metric-based appearance data for older settings documents.
        try values.encode(panelAppearances, forKey: .panelAppearances)
        try values.encode(panelColumns, forKey: .panelColumns)
        try values.encode(panelCardWidth, forKey: .panelCardWidth)
        try values.encode(showBandwidth, forKey: .showBandwidth)
        try values.encode(bandwidthInBits, forKey: .bandwidthInBits)
        try values.encode(networkInterface, forKey: .networkInterface)
        try values.encode(networkCeiling, forKey: .networkCeiling)
        try values.encode(uploadCeiling, forKey: .uploadCeiling)
        try values.encode(refreshInterval, forKey: .refreshInterval)
        try values.encode(monochrome, forKey: .monochrome)
        try values.encode(capacityUnits, forKey: .capacityUnits)
        try values.encode(bandwidthUnits, forKey: .bandwidthUnits)
    }

    /// Full-scale rate for a network direction; download for anything else.
    public func networkCeiling(for metric: MetricID) -> Double {
        metric == .upload ? uploadCeiling : networkCeiling
    }

    public func panelAppearance(for metric: MetricID) -> PanelAppearance {
        panels.first { $0.metric == metric }?.appearance ?? legacyPanelAppearances[metric.rawValue] ?? PanelAppearance()
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
        result.panels = Array(panels.prefix(32)).map { $0.validated() }
        var panelIDs: Set<UUID> = []
        for index in result.panels.indices {
            while !panelIDs.insert(result.panels[index].id).inserted { result.panels[index].id = UUID() }
        }
        result.panelColumns = min(8, max(1, panelColumns))
        result.panelCardWidth = panelCardWidth.isFinite ? min(240, max(120, panelCardWidth)) : 156
        result.legacyPanelAppearances = legacyPanelAppearances.filter { MetricID(rawValue: $0.key) != nil }
        if !networkCeiling.isFinite || networkCeiling <= 0 { result.networkCeiling = defaults.networkCeiling }
        if !uploadCeiling.isFinite || uploadCeiling <= 0 { result.uploadCeiling = result.networkCeiling }
        result.refreshInterval = refreshInterval.isFinite ? min(60, max(1, refreshInterval)) : defaults.refreshInterval
        result.networkInterface = cleanedInterface(networkInterface)
        return result
    }
}
