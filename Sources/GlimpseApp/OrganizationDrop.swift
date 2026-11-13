import SwiftUI
import UniformTypeIdentifiers
import GlimpseCore

enum OrganizationDragPayload {
    enum Kind { case column, panel }
    case column(UUID)
    case panel(MetricID)

    var text: String {
        switch self {
        case .column(let id): return "glimpse.column.\(id.uuidString)"
        case .panel(let metric): return "glimpse.panel.\(metric.rawValue)"
        }
    }

    init?(text: String, kind: Kind) {
        switch kind {
        case .column:
            let prefix = "glimpse.column."
            guard text.hasPrefix(prefix), let id = UUID(uuidString: String(text.dropFirst(prefix.count))) else { return nil }
            self = .column(id)
        case .panel:
            let prefix = "glimpse.panel."
            guard text.hasPrefix(prefix), let metric = MetricID(rawValue: String(text.dropFirst(prefix.count))) else { return nil }
            self = .panel(metric)
        }
    }

    var provider: NSItemProvider { NSItemProvider(object: text as NSString) }
}

/// Reordering happens only after a completed drop. No shared drag identity is retained.
struct OrganizationDropDelegate: DropDelegate {
    let kind: OrganizationDragPayload.Kind
    let perform: @MainActor (OrganizationDragPayload) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.text]) }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first,
              provider.canLoadObject(ofClass: NSString.self) else { return false }
        provider.loadObject(ofClass: NSString.self) { object, error in
            guard error == nil, let text = object as? String,
                  let payload = OrganizationDragPayload(text: text, kind: kind) else { return }
            DispatchQueue.main.async { perform(payload) }
        }
        return true
    }
}

@MainActor
func columnDrop(store: MonitoringStore, before target: UUID?) -> OrganizationDropDelegate {
    OrganizationDropDelegate(kind: .column) { payload in
        guard case .column(let id) = payload else { return }
        store.change { settings in
            guard settings.columns.contains(where: { $0.id == id }),
                  target == nil || settings.columns.contains(where: { $0.id == target }) else { return }
            _ = WidgetOrganization.moveColumn(in: &settings, id: id, before: target)
        }
    }
}

@MainActor
func panelDrop(store: MonitoringStore, before target: MetricID?) -> OrganizationDropDelegate {
    OrganizationDropDelegate(kind: .panel) { payload in
        guard case .panel(let metric) = payload else { return }
        store.change { settings in
            guard settings.panelMetrics.contains(metric),
                  target == nil || settings.panelMetrics.contains(where: { $0 == target }) else { return }
            _ = WidgetOrganization.movePanel(in: &settings, metric: metric, before: target)
        }
    }
}
