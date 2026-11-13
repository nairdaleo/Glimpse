import Foundation
import Darwin
import SystemConfiguration

struct InterfaceCounter {
    let name: String
    let index: UInt32
    let flags: Int32
    let received: UInt64
    let sent: UInt64
    var identity: String { "\(name):\(index)" }
    var usable: Bool { flags & Int32(IFF_UP) != 0 && flags & Int32(IFF_RUNNING) != 0 && flags & Int32(IFF_LOOPBACK) == 0 }
}

enum NativeReadError: Error, CustomStringConvertible {
    case system(String, Int32)
    case malformedRoute
    var description: String {
        switch self {
        case .system(let operation, let code): return "\(operation) unavailable (\(code))"
        case .malformedRoute: return "Interface counter response was incomplete"
        }
    }
}

enum InterfaceCounterParser {
    /// Route records are variable length. Copy into aligned storage instead of
    /// binding Data's potentially unaligned bytes to a C struct.
    static func parse(_ data: Data, name: (UInt32) -> String?) throws -> [InterfaceCounter] {
        var result: [InterfaceCounter] = []
        var offset = 0
        while offset < data.count {
            guard data.count - offset >= 4 else { throw NativeReadError.malformedRoute }
            var length: UInt16 = 0
            _ = withUnsafeMutableBytes(of: &length) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
            let count = Int(length)
            guard count >= 4, count <= data.count - offset else { throw NativeReadError.malformedRoute }
            if data[offset + 3] == UInt8(RTM_IFINFO2) {
                guard count >= MemoryLayout<if_msghdr2>.size else { throw NativeReadError.malformedRoute }
                var header = if_msghdr2()
                _ = withUnsafeMutableBytes(of: &header) { data.copyBytes(to: $0, from: offset..<(offset + MemoryLayout<if_msghdr2>.size)) }
                guard header.ifm_version == UInt8(RTM_VERSION) else { throw NativeReadError.malformedRoute }
                let index = UInt32(header.ifm_index)
                if let interfaceName = name(index) {
                    result.append(InterfaceCounter(name: interfaceName, index: index, flags: header.ifm_flags,
                                                   received: header.ifm_data.ifi_ibytes, sent: header.ifm_data.ifi_obytes))
                }
            }
            offset += count
        }
        return result
    }
}

enum InterfaceSelection {
    /// Exactly one interface is returned; physical and tunnel traffic are never summed.
    static func select(_ interfaces: [InterfaceCounter], preferred: String?, primary: String?, physical: Set<String>) -> InterfaceCounter? {
        let usable = interfaces.filter(\.usable)
        if let preferred { return usable.first { $0.name == preferred } }
        let physicalInterfaces = usable.filter { physical.contains($0.name) }
        if let primary, let match = physicalInterfaces.first(where: { $0.name == primary }) { return match }
        return physicalInterfaces.sorted { $0.index < $1.index }.first
    }
}

struct InterfaceRateTracker {
    private var previous: (identity: String, received: UInt64, sent: UInt64, timestamp: TimeInterval)?
    mutating func reset() { previous = nil }
    mutating func update(identity: String, received: UInt64, sent: UInt64, timestamp: TimeInterval) -> (download: Double, upload: Double)? {
        let old = previous
        previous = (identity, received, sent, timestamp)
        guard let old, old.identity == identity, timestamp.isFinite, old.timestamp.isFinite,
              timestamp > old.timestamp, received >= old.received, sent >= old.sent else { return nil }
        let elapsed = timestamp - old.timestamp
        return (Double(received - old.received) / elapsed, Double(sent - old.sent) / elapsed)
    }
}

enum NativeNetworkReader {
    static func readCounters() throws -> [InterfaceCounter] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        // Interface creation can grow the buffer between the size and data calls.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else {
                throw NativeReadError.system("Interface counters", errno)
            }
            var data = Data(count: size)
            let code = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) }
            if code == 0 {
                data.count = size
                return try InterfaceCounterParser.parse(data) { index in
                    var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    guard if_indextoname(index, &buffer) != nil else { return nil }
                    return String(cString: buffer)
                }
            }
            if errno != ENOMEM { throw NativeReadError.system("Interface counters", errno) }
        }
        throw NativeReadError.system("Interface counters changed during read", ENOMEM)
    }

    static func physicalInterfaces() -> Set<String> {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        let physicalTypes = [kSCNetworkInterfaceTypeEthernet, kSCNetworkInterfaceTypeIEEE80211, kSCNetworkInterfaceTypeWWAN, kSCNetworkInterfaceTypeBluetooth].map { $0 as String }
        return Set(interfaces.compactMap { interface in
            guard let type = SCNetworkInterfaceGetInterfaceType(interface) as String?, physicalTypes.contains(type),
                  let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            return name
        })
    }

    static func primaryInterface() -> String? {
        for family in ["IPv4", "IPv6"] {
            let key = "State:/Network/Global/\(family)" as CFString
            if let state = SCDynamicStoreCopyValue(nil, key) as? [String: Any],
               let name = state[kSCDynamicStorePropNetPrimaryInterface as String] as? String { return name }
        }
        return nil
    }
}
