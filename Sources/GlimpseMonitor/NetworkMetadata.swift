import Foundation
import Darwin
import SystemConfiguration
import GlimpseCore

enum NativeNetworkMetadata {
    /// This collector is called only for visible configuration/details, at a
    /// bounded cadence. Numeric address conversion performs no DNS lookup.
    static func read(_ counters: [InterfaceCounter]) -> [NetworkInterfaceInfo] {
        var descriptions: [String: (displayName: String, kind: String)] = [:]
        if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in interfaces {
                guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
                let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
                let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? name
                let kind: String
                if type == (kSCNetworkInterfaceTypeIEEE80211 as String) { kind = "Wi-Fi" }
                else if type == (kSCNetworkInterfaceTypeEthernet as String) { kind = "Wired" }
                else if type == (kSCNetworkInterfaceTypeWWAN as String) { kind = "Cellular" }
                else if type == (kSCNetworkInterfaceTypeBluetooth as String) { kind = "Bluetooth" }
                else { kind = fallbackKind(name: name, flags: 0) }
                descriptions[name] = (displayName, kind)
            }
        }
        let addresses = localAddresses()
        let patterns = ["State:/Network/Service/[^/]+/(IPv4|IPv6|DNS)", "Setup:/Network/Service/[^/]+/Interface"] as CFArray
        let values = SCDynamicStoreCopyMultiple(nil, nil, patterns) as? [String: Any] ?? [:]
        let dns = DNSConfiguration.byInterface(storeValues: values)
        let counterByName = Dictionary(counters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Set(counterByName.keys).union(descriptions.keys)
        return names.sorted().map { name in
            let flags = counterByName[name]?.flags ?? 0
            return NetworkInterfaceInfo(name: name, displayName: descriptions[name]?.displayName ?? name,
                                        kind: descriptions[name]?.kind ?? fallbackKind(name: name, flags: flags),
                                        isUp: flags & Int32(IFF_UP) != 0, isRunning: flags & Int32(IFF_RUNNING) != 0,
                                        ipv4Addresses: addresses[name]?.ipv4 ?? [], ipv6Addresses: addresses[name]?.ipv6 ?? [],
                                        dnsServers: dns[name]?.servers ?? [], searchDomains: dns[name]?.searchDomains ?? [])
        }
    }

    private static func fallbackKind(name: String, flags: Int32) -> String {
        if flags & Int32(IFF_LOOPBACK) != 0 || name == "lo0" { return "Loopback" }
        if ["utun", "tun", "tap", "ppp", "ipsec"].contains(where: name.hasPrefix) { return "Tunnel" }
        return "Other"
    }

    private static func localAddresses() -> [String: (ipv4: [String], ipv6: [String])] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [:] }
        defer { freeifaddrs(first) }
        var result: [String: (ipv4: [String], ipv6: [String])] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard length > 0, getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            let value = String(cString: host)
            var pair = result[name] ?? ([], [])
            if family == AF_INET { pair.ipv4.append(value) } else { pair.ipv6.append(value) }
            result[name] = pair
        }
        return result.mapValues { (Array(Set($0.ipv4)).sorted(), Array(Set($0.ipv6)).sorted()) }
    }
}

struct DNSConfiguration {
    var servers: [String]
    var searchDomains: [String]

    /// Service-scoped DNS belongs only to that service's interface. Global and
    /// supplemental resolver data are not presented as another NIC's settings.
    static func byInterface(storeValues: [String: Any]) -> [String: DNSConfiguration] {
        var result: [String: DNSConfiguration] = [:]
        for (key, value) in storeValues where key.hasPrefix("State:/Network/Service/") && key.hasSuffix("/DNS") {
            guard let dns = value as? [String: Any] else { continue }
            let components = key.split(separator: "/")
            guard components.count == 5 else { continue }
            let service = String(components[3])
            let prefix = "State:/Network/Service/\(service)/"
            let ipv4 = storeValues[prefix + "IPv4"] as? [String: Any]
            let ipv6 = storeValues[prefix + "IPv6"] as? [String: Any]
            let setup = storeValues["Setup:/Network/Service/\(service)/Interface"] as? [String: Any]
            guard let name = ipv4?[kSCPropInterfaceName as String] as? String
                    ?? ipv6?[kSCPropInterfaceName as String] as? String
                    ?? setup?[kSCPropNetInterfaceDeviceName as String] as? String else { continue }
            let servers = dns[kSCPropNetDNSServerAddresses as String] as? [String] ?? []
            let search = dns[kSCPropNetDNSSearchDomains as String] as? [String] ?? []
            let previous = result[name]
            result[name] = DNSConfiguration(servers: Array(Set((previous?.servers ?? []) + servers)).sorted(),
                                             searchDomains: Array(Set((previous?.searchDomains ?? []) + search)).sorted())
        }
        return result
    }
}
