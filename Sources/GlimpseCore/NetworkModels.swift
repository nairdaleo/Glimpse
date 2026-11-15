import Foundation

/// One actual interface's rates. Identity includes the kernel interface index so
/// a recreated device cannot silently continue the old device's history.
public struct NetworkInterfaceReading: Sendable {
    public var identity: String
    public var name: String
    public var download: MetricReading
    public var upload: MetricReading

    public init(identity: String, name: String, download: MetricReading, upload: MetricReading) {
        self.identity = identity
        self.name = name
        self.download = download
        self.upload = upload
    }
}

/// Locally reported interface configuration; DNS/search domains describe resolver
/// settings, never visited websites or proof of internet connectivity.
public struct NetworkInterfaceInfo: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var displayName: String
    public var kind: String
    public var isUp: Bool
    public var isRunning: Bool
    public var ipv4Addresses: [String]
    public var ipv6Addresses: [String]
    public var dnsServers: [String]
    public var searchDomains: [String]
    public var subnetMasks: [String]
    public var routers: [String]
    public var macAddress: String?
    /// Configured proxies, e.g. "HTTPS proxy.example:8080"; empty when none.
    public var proxies: [String]
    public var id: String { name }

    public init(name: String, displayName: String, kind: String, isUp: Bool, isRunning: Bool,
                ipv4Addresses: [String] = [], ipv6Addresses: [String] = [], dnsServers: [String] = [], searchDomains: [String] = [],
                subnetMasks: [String] = [], routers: [String] = [], macAddress: String? = nil, proxies: [String] = []) {
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.isUp = isUp
        self.isRunning = isRunning
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.dnsServers = dnsServers
        self.searchDomains = searchDomains
        self.subnetMasks = subnetMasks
        self.routers = routers
        self.macAddress = macAddress
        self.proxies = proxies
    }

    public var statusText: String { isUp ? (isRunning ? String(localized: "Active") : String(localized: "Enabled, no link")) : String(localized: "Inactive") }

    /// Label/value rows for the chosen fields, in a fixed reading order.
    /// Extra values get an empty label; missing values read "—"; proxy rows
    /// appear only when a proxy is configured.
    public func detailRows(_ fields: Set<NetworkDetailField> = Set(NetworkDetailField.allCases)) -> [(label: String, value: String)] {
        NetworkDetailField.allCases.filter(fields.contains).flatMap(rows)
    }

    /// Fields in usefulness order (limited to `among` when chosen manually),
    /// each included only when all of its rows still fit in `capacity`, so
    /// nothing is cut off; larger cards show more.
    public func fittedRows(capacity: Int, among fields: Set<NetworkDetailField>? = nil) -> [(label: String, value: String)] {
        var remaining = max(0, capacity)
        var chosen: Set<NetworkDetailField> = []
        for field in NetworkDetailField.priority where fields?.contains(field) ?? true {
            let count = rows(for: field).count
            guard count > 0, count <= remaining else { continue }
            chosen.insert(field)
            remaining -= count
        }
        return NetworkDetailField.priority.filter(chosen.contains).flatMap(rows)
    }

    private func rows(for field: NetworkDetailField) -> [(label: String, value: String)] {
        let values: [String]
        switch field {
        case .status: values = [statusText]
        case .ipv4: values = ipv4Addresses
        case .subnetMask: values = subnetMasks
        case .router: values = routers
        case .ipv6: values = ipv6Addresses
        case .dns: values = dnsServers
        case .searchDomains: values = searchDomains
        case .mac: values = macAddress.map { [$0] } ?? []
        case .proxy: values = proxies
        }
        if values.isEmpty { return field == .proxy ? [] : [(field.label, "—")] }
        return values.enumerated().map { (index, value) in (index == 0 ? field.label : "", value) }
    }
}

public enum NetworkDetailField: String, Codable, CaseIterable, Identifiable, Sendable {
    case status, ipv4, subnetMask, router, ipv6, dns, searchDomains, mac, proxy
    public var id: String { rawValue }
    /// Most useful first; the order automatic selection fills a card in.
    public static let priority: [NetworkDetailField] = [.ipv4, .router, .dns, .subnetMask, .mac, .searchDomains, .status, .ipv6, .proxy]
    /// Short row label for cards.
    public var label: String {
        switch self {
        case .status: return String(localized: "Status")
        case .ipv4: return "IPv4"
        case .subnetMask: return String(localized: "Mask")
        case .router: return String(localized: "Router")
        case .ipv6: return "IPv6"
        case .dns: return "DNS"
        case .searchDomains: return String(localized: "Search")
        case .mac: return "MAC"
        case .proxy: return String(localized: "Proxy")
        }
    }
    /// Full name for settings.
    public var title: String {
        switch self {
        case .status: return String(localized: "Link status")
        case .ipv4: return String(localized: "IPv4 address")
        case .subnetMask: return String(localized: "Subnet mask")
        case .router: return String(localized: "Router")
        case .ipv6: return String(localized: "IPv6 address")
        case .dns: return String(localized: "DNS servers")
        case .searchDomains: return String(localized: "Search domains")
        case .mac: return String(localized: "MAC address")
        case .proxy: return String(localized: "Proxy (if set)")
        }
    }
}
