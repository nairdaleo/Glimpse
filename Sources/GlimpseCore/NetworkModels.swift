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
    public var id: String { name }

    public init(name: String, displayName: String, kind: String, isUp: Bool, isRunning: Bool,
                ipv4Addresses: [String] = [], ipv6Addresses: [String] = [], dnsServers: [String] = [], searchDomains: [String] = []) {
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.isUp = isUp
        self.isRunning = isRunning
        self.ipv4Addresses = ipv4Addresses
        self.ipv6Addresses = ipv6Addresses
        self.dnsServers = dnsServers
        self.searchDomains = searchDomains
    }
}
