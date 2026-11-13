import Foundation

public enum WidgetOrganization: Sendable {
    @discardableResult
    public static func moveColumn(in settings: inout AppSettings, id: UUID, before target: UUID?) -> Bool {
        guard let source = settings.columns.firstIndex(where: { $0.id == id }), target != id else { return false }
        let destination: Int
        if let target {
            guard let index = settings.columns.firstIndex(where: { $0.id == target }) else { return false }
            destination = index - (source < index ? 1 : 0)
        } else { destination = settings.columns.count - 1 }
        guard source != destination else { return false }
        let column = settings.columns.remove(at: source)
        settings.columns.insert(column, at: destination)
        return true
    }

    @discardableResult
    public static func addColumn(to settings: inout AppSettings, metric: MetricID) -> UUID? {
        guard settings.columns.count < 8 else { return nil }
        var column = ColumnConfiguration(metric: metric, colour: .mint)
        while settings.columns.contains(where: { $0.id == column.id }) { column.id = UUID() }
        settings.columns.append(column)
        return column.id
    }

    @discardableResult
    public static func removeColumn(from settings: inout AppSettings, id: UUID) -> Bool {
        guard settings.columns.count > 1, let index = settings.columns.firstIndex(where: { $0.id == id }) else { return false }
        settings.columns.remove(at: index)
        return true
    }

    @discardableResult
    public static func movePanel(in settings: inout AppSettings, metric: MetricID, before target: MetricID?) -> Bool {
        guard let source = settings.panelMetrics.firstIndex(of: metric), target != metric else { return false }
        let destination: Int
        if let target {
            guard let index = settings.panelMetrics.firstIndex(of: target) else { return false }
            destination = index - (source < index ? 1 : 0)
        } else { destination = settings.panelMetrics.count - 1 }
        guard source != destination else { return false }
        settings.panelMetrics.remove(at: source)
        settings.panelMetrics.insert(metric, at: destination)
        return true
    }

    public static func setPanel(in settings: inout AppSettings, metric: MetricID, visible: Bool) {
        if visible {
            if !settings.panelMetrics.contains(metric) { settings.panelMetrics.append(metric) }
        } else {
            settings.panelMetrics.removeAll { $0 == metric }
        }
    }
}
