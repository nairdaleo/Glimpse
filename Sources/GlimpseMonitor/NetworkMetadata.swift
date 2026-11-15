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
                if type == (kSCNetworkInterfaceTypeIEEE80211 as String) { kind = String(localized: "Wi-Fi") }
                else if type == (kSCNetworkInterfaceTypeEthernet as String) { kind = String(localized: "Wired") }
                else if type == (kSCNetworkInterfaceTypeWWAN as String) { kind = String(localized: "Cellular") }
                else if type == (kSCNetworkInterfaceTypeBluetooth as String) { kind = String(localized: "Bluetooth") }
                else { kind = fallbackKind(name: name, flags: 0) }
                descriptions[name] = (displayName, kind)
            }
        }
        let addresses = localAddresses()
        let patterns = ["State:/Network/Service/[^/]+/(IPv4|IPv6|DNS)", "Setup:/Network/Service/[^/]+/Interface"] as CFArray
        let values = SCDynamicStoreCopyMultiple(nil, nil, patterns) as? [String: Any] ?? [:]
        let dns = DNSConfiguration.byInterface(storeValues: values)
        let routers = routersByInterface(storeValues: values)
        let proxies = SCDynamicStoreCopyProxies(nil) as? [String: Any] ?? [:]
        let counterByName = Dictionary(counters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Set(counterByName.keys).union(descriptions.keys)
        return names.sorted().map { name in
            let flags = counterByName[name]?.flags ?? 0
            return NetworkInterfaceInfo(name: name, displayName: descriptions[name]?.displayName ?? name,
                                        kind: descriptions[name]?.kind ?? fallbackKind(name: name, flags: flags),
                                        isUp: flags & Int32(IFF_UP) != 0, isRunning: flags & Int32(IFF_RUNNING) != 0,
                                        ipv4Addresses: addresses[name]?.ipv4 ?? [], ipv6Addresses: addresses[name]?.ipv6 ?? [],
                                        dnsServers: dns[name]?.servers ?? [], searchDomains: dns[name]?.searchDomains ?? [],
                                        subnetMasks: addresses[name]?.masks ?? [], routers: routers[name] ?? [],
                                        macAddress: addresses[name]?.mac, proxies: proxySummary(proxies, interface: name))
        }
    }

    private static func fallbackKind(name: String, flags: Int32) -> String {
        if flags & Int32(IFF_LOOPBACK) != 0 || name == "lo0" { return String(localized: "Loopback") }
        if ["utun", "tun", "tap", "ppp", "ipsec"].contains(where: name.hasPrefix) { return String(localized: "Tunnel") }
        return String(localized: "Other")
    }

    struct LocalAddresses { var ipv4: [String] = []; var ipv6: [String] = []; var masks: [String] = []; var mac: String? }

    private static func localAddresses() -> [String: LocalAddresses] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [:] }
        defer { freeifaddrs(first) }
        func numeric(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard length > 0, getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
            return String(cString: host)
        }
        var result: [String: LocalAddresses] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            var info = result[name] ?? LocalAddresses()
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                guard let value = numeric(address) else { continue }
                info.ipv4.append(value)
                if let mask = entry.pointee.ifa_netmask, let text = numeric(mask) { info.masks.append(text) }
            case AF_INET6:
                guard let value = numeric(address) else { continue }
                info.ipv6.append(value)
            case AF_LINK:
                info.mac = address.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { link in
                    let dl = link.pointee
                    guard dl.sdl_alen == 6 else { return nil }
                    return withUnsafeBytes(of: dl.sdl_data) { data in
                        let start = Int(dl.sdl_nlen)
                        guard start + 6 <= data.count else { return nil }
                        return (start..<start + 6).map { String(format: "%02x", data[$0]) }.joined(separator: ":")
                    }
                }
            default: continue
            }
            result[name] = info
        }
        return result.mapValues { LocalAddresses(ipv4: Array(Set($0.ipv4)).sorted(), ipv6: Array(Set($0.ipv6)).sorted(),
                                                 masks: Array(Set($0.masks)).sorted(), mac: $0.mac) }
    }

    /// IPv4 router per interface from service state.
    static func routersByInterface(storeValues: [String: Any]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (key, value) in storeValues where key.hasPrefix("State:/Network/Service/") && key.hasSuffix("/IPv4") {
            guard let ipv4 = value as? [String: Any], let name = ipv4[kSCPropInterfaceName as String] as? String,
                  let router = ipv4[kSCPropNetIPv4Router as String] as? String else { continue }
            result[name, default: []].append(router)
        }
        return result.mapValues { Array(Set($0)).sorted() }
    }

    /// Enabled proxies for an interface: its scoped settings when present,
    /// otherwise the system-wide ones. Empty means none configured.
    static func proxySummary(_ proxies: [String: Any], interface: String) -> [String] {
        let settings = (proxies["__SCOPED__"] as? [String: Any])?[interface] as? [String: Any] ?? proxies
        func enabled(_ key: String) -> Bool { (settings[key] as? NSNumber)?.boolValue == true }
        var result: [String] = []
        for (name, enable, host, port) in [("HTTP", "HTTPEnable", "HTTPProxy", "HTTPPort"),
                                           ("HTTPS", "HTTPSEnable", "HTTPSProxy", "HTTPSPort"),
                                           ("SOCKS", "SOCKSEnable", "SOCKSProxy", "SOCKSPort")] where enabled(enable) {
            guard let server = settings[host] as? String, !server.isEmpty else { continue }
            let portText = (settings[port] as? NSNumber).map { ":\($0)" } ?? ""
            result.append("\(name) \(server)\(portText)")
        }
        if enabled("ProxyAutoConfigEnable"), let url = settings["ProxyAutoConfigURLString"] as? String, !url.isEmpty {
            result.append("PAC \(url)")
        }
        if enabled("ProxyAutoDiscoveryEnable") { result.append(String(localized: "Auto-discovery")) }
        return result
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
