import Foundation

public struct MetricHistory: Sendable {
    public private(set) var samples: [MetricID: [HistoryPoint]] = [:]
    private var latestTimestamp: TimeInterval?
    public init() {}

    public mutating func append(_ snapshot: Snapshot) {
        guard snapshot.timestamp.isFinite else { return }
        let now = max(latestTimestamp ?? snapshot.timestamp, snapshot.timestamp)
        latestTimestamp = now
        let cutoff = now - 300
        for metric in MetricID.allCases {
            var points = samples[metric] ?? []
            if let reading = snapshot.readings[metric], reading.timestamp.isFinite,
               reading.timestamp >= cutoff, reading.timestamp <= now,
               points.last.map({ reading.timestamp > $0.timestamp }) ?? true {
                let finiteValue = reading.value.flatMap { $0.isFinite ? $0 : nil }
                points.append(HistoryPoint(timestamp: reading.timestamp, value: finiteValue))
            }
            // Mark the first unsampled interval so a resumed collector cannot draw
            // a line across it. Subsequent absent snapshots retain this single gap.
            if snapshot.readings[metric] == nil, let last = points.last,
               last.value != nil, snapshot.timestamp > last.timestamp {
                points.append(HistoryPoint(timestamp: snapshot.timestamp, value: nil))
            }
            points.removeAll { $0.timestamp < cutoff }
            if points.count > 600 { points.removeFirst(points.count - 600) }
            if !points.isEmpty || samples[metric] != nil { samples[metric] = points }
        }
    }
}
