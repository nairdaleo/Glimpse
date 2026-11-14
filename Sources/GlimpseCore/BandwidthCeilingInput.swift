/// Converts the ceiling editor's mega-units while storage remains bytes/second.
public enum BandwidthCeilingInput: Sendable {
    private static func mega(_ units: CapacityUnits) -> Double { units == .si ? 1_000_000 : 1_048_576 }

    public static func displayValue(bytesPerSecond: Double, bits: Bool, units: CapacityUnits = .si) -> Double {
        bytesPerSecond / mega(units) * (bits ? 8 : 1)
    }

    public static func bytesPerSecond(displayValue: Double, bits: Bool, units: CapacityUnits = .si) -> Double {
        displayValue / (bits ? 8 : 1) * mega(units)
    }

    public static func unit(bits: Bool, units: CapacityUnits = .si) -> String {
        (units == .si ? "M" : "Mi") + (bits ? "b/s" : "B/s")
    }
}
