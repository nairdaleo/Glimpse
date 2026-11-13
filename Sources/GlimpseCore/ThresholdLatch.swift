import Foundation

public enum ThresholdLevel: Int, Sendable {
    case normal, warning, critical
}

/// Escalate immediately; release a warning only after crossing its small deadband.
/// This stabilizes colour without smoothing or altering the displayed measurement.
public struct ThresholdLatch: Sendable {
    private var previous: ThresholdLevel?
    private var configuration: ColumnConfiguration?
    public init() {}

    public mutating func evaluate(value: Double?, column: ColumnConfiguration, deadband: Double) -> ThresholdLevel? {
        if configuration != column { previous = nil; configuration = column }
        guard let value = value, value.isFinite else { previous = nil; return nil }
        let margin = deadband.isFinite ? max(0, deadband) : 0
        func crossed(_ threshold: Double?, retaining level: ThresholdLevel) -> Bool {
            guard let threshold = threshold, threshold.isFinite else { return false }
            let retain = (previous?.rawValue ?? 0) >= level.rawValue
            // A deadband must leave room to return to normal at reachable values.
            // In particular a large bandwidth scale cannot latch a small threshold
            // at zero traffic, nor can a below-percent threshold latch at 100%.
            let distance: Double
            if column.thresholdDirection == .above {
                distance = max(0, threshold)
            } else if column.metric == .download || column.metric == .upload {
                distance = max(0, threshold)
            } else {
                distance = max(0, (column.metric == .thermal ? 3 : 100) - threshold)
            }
            let releaseMargin = min(margin, distance * 0.5)
            switch column.thresholdDirection {
            case .above: return value >= threshold - (retain ? releaseMargin : 0)
            case .below: return value <= threshold + (retain ? releaseMargin : 0)
            }
        }
        let result: ThresholdLevel
        if crossed(column.criticalThreshold, retaining: .critical) { result = .critical }
        else if crossed(column.warningThreshold, retaining: .warning) { result = .warning }
        else { result = .normal }
        previous = result
        return result
    }
}
