import Foundation

/// Rate history belongs to an actual interface identity, never to an Auto selector.
public struct NetworkHistory: Sendable {
    private var histories: [String: MetricHistory] = [:]
    public init() {}

    public mutating func append(_ snapshot: Snapshot) {
        guard snapshot.timestamp.isFinite else { return }
        let incoming = snapshot.networkReadings.values.reduce(into: [String: NetworkInterfaceReading]()) { $0[$1.identity] = $1 }
        for identity in Set(histories.keys).union(incoming.keys) {
            var history = histories[identity] ?? MetricHistory()
            let readings: [MetricID: MetricReading]
            if let reading = incoming[identity] { readings = [.download: reading.download, .upload: reading.upload] }
            else { readings = [:] }
            history.append(Snapshot(timestamp: snapshot.timestamp, readings: readings))
            if history.samples.values.allSatisfy(\.isEmpty) { histories.removeValue(forKey: identity) }
            else { histories[identity] = history }
        }
        // Bound memory even when devices are repeatedly recreated during the retention window.
        if histories.count > 32 {
            let keep = histories.keys.sorted { latest($0) > latest($1) }.prefix(32)
            histories = histories.filter { keep.contains($0.key) }
        }
    }

    public func points(for metric: MetricID, interface: String?, snapshot: Snapshot) -> [HistoryPoint] {
        guard let name = interface ?? snapshot.automaticNetworkInterface,
              let reading = snapshot.networkReadings[name] else { return [] }
        return histories[reading.identity]?.samples[metric] ?? []
    }

    private func latest(_ identity: String) -> TimeInterval {
        histories[identity]?.samples.values.compactMap { $0.last?.timestamp }.max() ?? -.infinity
    }
}
