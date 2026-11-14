/// Converts the ceiling editor's decimal units while storage remains bytes/second.
public enum BandwidthCeilingInput: Sendable {
    public static func displayValue(bytesPerSecond: Double, bits: Bool) -> Double {
        bytesPerSecond / 1_000_000 * (bits ? 8 : 1)
    }

    public static func bytesPerSecond(displayValue: Double, bits: Bool) -> Double {
        displayValue / (bits ? 8 : 1) * 1_000_000
    }

    public static func unit(bits: Bool) -> String {
        bits ? "Mb/s" : "MB/s"
    }
}
