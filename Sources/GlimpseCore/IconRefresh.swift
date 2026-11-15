/// What one meter shows: its fill (0...1, nil when unavailable) and threshold level.
public struct MeterState: Equatable, Sendable {
    public var fill: Double?
    public var level: ThresholdLevel?
    public init(fill: Double?, level: ThresholdLevel?) {
        self.fill = fill
        self.level = level
    }
}

public enum IconRefresh {
    /// Each menu-bar image change makes WindowServer recomposite the menu bar, which costs
    /// more than sampling. Redraw only when a meter visibly moves (more than `tolerance` of its
    /// height), changes threshold level, or becomes available/unavailable.
    public static func needsRedraw(shown: [MeterState]?, next: [MeterState], tolerance: Double = 0.05) -> Bool {
        guard let shown, shown.count == next.count else { return true }
        return zip(shown, next).contains { old, new in
            guard old.level == new.level else { return true }
            switch (old.fill, new.fill) {
            case (nil, nil): return false
            case let (a?, b?): return abs(a - b) > tolerance
            default: return true
            }
        }
    }
}
