import SwiftUI
import GlimpseCore

extension Snapshot {
    func displayReading(for metric: MetricID, interface: String?) -> MetricReading? {
        if metric == .upload || metric == .download { return networkReading(for: metric, interface: interface) }
        return readings[metric]
    }

    func interfaceLabel(_ selected: String?) -> String {
        let name = selected ?? automaticNetworkInterface
        guard let name else { return "no active physical interface" }
        let info = interfaceDetails.first { $0.name == name }
        return name + (info.map { " · \($0.kind)" } ?? "")
    }
}

struct NetworkInterfacePicker: View {
    var title = "Interface"
    @Binding var selection: String?
    let snapshot: Snapshot

    private var names: [String] {
        Set(snapshot.availableInterfaces + snapshot.interfaceDetails.map(\.name) + [selection].compactMap { $0 }).sorted()
    }
    var body: some View {
        Picker(title, selection: $selection) {
            Text("Auto · \(snapshot.interfaceLabel(nil))").tag(Optional<String>.none)
            ForEach(names, id: \.self) { name in
                Text(snapshot.interfaceLabel(name)).tag(Optional(name))
            }
        }
        .help("Auto follows the active physical interface. Each meter and card can select a different interface.")
    }
}

struct NetworkInterfaceDetails: View {
    let info: NetworkInterfaceInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(info.displayName) · \(info.kind)").font(.callout)
            Text(info.isUp ? (info.isRunning ? "Active interface" : "Enabled · no active link") : "Inactive interface")
                .font(.caption).foregroundColor(.secondary)
            details("IPv4", info.ipv4Addresses)
            details("IPv6", info.ipv6Addresses)
            details("DNS servers", info.dnsServers)
            details("Search domains", info.searchDomains)
        }.textSelection(.enabled)
    }
    private func details(_ title: String, _ values: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title).foregroundColor(.secondary).frame(width: 94, alignment: .leading)
            Text(values.isEmpty ? "Not reported" : values.joined(separator: ", "))
                .frame(maxWidth: .infinity, alignment: .leading)
        }.font(.caption)
    }
}

struct SelectedInterfaceDetails: View {
    let selection: String?
    let snapshot: Snapshot
    var body: some View {
        let name = selection ?? snapshot.automaticNetworkInterface
        if let info = snapshot.interfaceDetails.first(where: { $0.name == name }) {
            DisclosureGroup("\(snapshot.interfaceLabel(selection)) details") {
                NetworkInterfaceDetails(info: info).padding(.top, 6)
            }.font(.caption)
        } else {
            Text(name.map { "\($0) is unavailable. The selection is kept for when it returns." } ?? "Waiting for an active physical interface.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
