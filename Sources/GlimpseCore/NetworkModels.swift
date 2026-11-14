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

    public var statusText: String { isUp ? (isRunning ? "Active" : "Enabled, no link") : "Inactive" }

    /// Label/value rows for the chosen fields, in a fixed reading order.
    /// Extra values get an empty label; missing values read "—"; proxy rows
    /// appear only when a proxy is configured.
    public func detailRows(_ fields: Set<NetworkDetailField> = Set(NetworkDetailField.allCases)) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        for field in NetworkDetailField.allCases where fields.contains(field) {
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
            if values.isEmpty {
                if field != .proxy { rows.append((field.label, "—")) }
                continue
            }
            for (index, value) in values.enumerated() { rows.append((index == 0 ? field.label : "", value)) }
        }
        return rows
    }
}

public enum NetworkDetailField: String, Codable, CaseIterable, Identifiable, Sendable {
    case status, ipv4, subnetMask, router, ipv6, dns, searchDomains, mac, proxy
    public var id: String { rawValue }
    /// Short row label for cards.
    public var label: String {
        switch self {
        case .status: return "Status"
        case .ipv4: return "IPv4"
        case .subnetMask: return "Mask"
        case .router: return "Router"
        case .ipv6: return "IPv6"
        case .dns: return "DNS"
        case .searchDomains: return "Search"
        case .mac: return "MAC"
        case .proxy: return "Proxy"
        }
    }
    /// Full name for settings.
    public var title: String {
        switch self {
        case .status: return "Link status"
        case .ipv4: return "IPv4 address"
        case .subnetMask: return "Subnet mask"
        case .router: return "Router"
        case .ipv6: return "IPv6 address"
        case .dns: return "DNS servers"
        case .searchDomains: return "Search domains"
        case .mac: return "MAC address"
        case .proxy: return "Proxy (if set)"
        }
    }
}
