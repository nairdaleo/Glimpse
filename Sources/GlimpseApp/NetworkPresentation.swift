import SwiftUI
import GlimpseCore

extension Snapshot {
    func displayReading(for metric: MetricID, interface: String?) -> MetricReading? {
        if metric == .upload || metric == .download { return networkReading(for: metric, interface: interface) }
        return readings[metric]
    }

    func interfaceLabel(_ selected: String?) -> String {
        let name = selected ?? automaticNetworkInterface
        guard let name else { return String(localized: "no active physical interface") }
        let info = interfaceDetails.first { $0.name == name }
        return name + (info.map { " · \($0.kind)" } ?? "")
    }
}

struct NetworkInterfacePicker: View {
    var title: LocalizedStringKey = "Interface"
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

/// One-line label/value rows; long values truncate in the middle and show
/// in full on hover. Selectable so addresses can be copied.
struct NetworkInterfaceDetails: View {
    let rows: [(label: String, value: String)]
    var size: CGFloat = 11

    init(rows: [(label: String, value: String)], size: CGFloat = 11) {
        self.rows = rows
        self.size = size
    }

    /// Every field, for Settings.
    init(info: NetworkInterfaceInfo) { self.init(rows: info.detailRows()) }

    /// Whole rows that fit `height`; line height is about 1.2 × the font size.
    static func capacity(height: CGFloat, size: CGFloat) -> Int {
        guard height.isFinite, height > 0 else { return 0 }
        return Int((height + size * 0.25) / (size * 1.2 + size * 0.25))
    }

    var body: some View {
        // The label column fits its longest label, so translated labels (Routeur, ルーター) never truncate.
        let font = NSFont.systemFont(ofSize: size)
        let labelWidth = ceil(rows.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 1
        VStack(alignment: .leading, spacing: size * 0.25) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rows[index].label).foregroundColor(.secondary).lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)
                    CopyableValue(value: rows[index].value)
                }
            }
        }.font(.system(size: size))
    }
}

/// A detail value that copies itself when clicked: pointing-hand cursor and accent colour on hover,
/// a "Click to copy" tooltip, and a brief "Copied" confirmation.
struct CopyableValue: View {
    let value: String
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        let copyable = value != "—" && !value.isEmpty
        Text(copied ? String(localized: "Copied") : value).lineLimit(1).truncationMode(.middle)
            .foregroundColor(copyable && hovering ? .accentColor : .primary)
            .contentShape(Rectangle())
            .onHover { inside in
                guard copyable else { return }
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                guard copyable else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            }
            .help(copyable ? String(localized: "Click to copy \(value)") : value)
            .accessibilityAddTraits(copyable ? .isButton : [])
            .accessibilityHint(copyable ? String(localized: "Copies the value") : "")
            .onDisappear { if hovering { NSCursor.pop() } }
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
