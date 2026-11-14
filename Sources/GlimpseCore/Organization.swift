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
        guard let id = settings.panels.first(where: { $0.metric == metric })?.id, target != metric else { return false }
        let targetID: UUID?
        if let target {
            guard let found = settings.panels.first(where: { $0.metric == target })?.id else { return false }
            targetID = found
        } else { targetID = nil }
        return movePanel(in: &settings, id: id, before: targetID)
    }

    @discardableResult
    public static func movePanel(in settings: inout AppSettings, id: UUID, before target: UUID?) -> Bool {
        guard let source = settings.panels.firstIndex(where: { $0.id == id }), target != id else { return false }
        let destination: Int
        if let target {
            guard let index = settings.panels.firstIndex(where: { $0.id == target }) else { return false }
            destination = index - (source < index ? 1 : 0)
        } else { destination = settings.panels.count - 1 }
        guard source != destination else { return false }
        let panel = settings.panels.remove(at: source)
        settings.panels.insert(panel, at: destination)
        return true
    }

    @discardableResult
    public static func addPanel(to settings: inout AppSettings, metric: MetricID, isCombinedNetwork: Bool = false, networkInterface: String? = nil, appearance: PanelAppearance = PanelAppearance()) -> UUID? {
        guard settings.panels.count + settings.hiddenPanels.count < 32 else { return nil }
        var panel = PanelConfiguration(metric: metric, isCombinedNetwork: isCombinedNetwork, networkInterface: networkInterface, appearance: appearance)
        while (settings.panels + settings.hiddenPanels).contains(where: { $0.id == panel.id }) { panel.id = UUID() }
        settings.panels.append(panel)
        return panel.id
    }

    @discardableResult
    public static func removePanel(from settings: inout AppSettings, id: UUID) -> Bool {
        let before = settings.panels.count + settings.hiddenPanels.count
        settings.panels.removeAll { $0.id == id }
        settings.hiddenPanels.removeAll { $0.id == id }
        return before != settings.panels.count + settings.hiddenPanels.count
    }

    @discardableResult
    public static func hidePanel(in settings: inout AppSettings, id: UUID) -> Bool {
        guard let panel = settings.panels.first(where: { $0.id == id }) else { return false }
        setPanel(in: &settings, panel: panel, visible: false)
        return true
    }

    @discardableResult
    public static func restorePanel(in settings: inout AppSettings, id: UUID) -> Bool {
        guard let panel = settings.hiddenPanels.first(where: { $0.id == id }) else { return false }
        setPanel(in: &settings, panel: panel, visible: true)
        return true
    }

    public static func setPanel(in settings: inout AppSettings, panel: PanelConfiguration, visible: Bool) {
        if visible {
            guard !settings.panels.contains(where: { $0.id == panel.id }) else { return }
            let existing = settings.hiddenPanels.first { $0.id == panel.id } ?? panel
            guard settings.hiddenPanels.contains(where: { $0.id == panel.id }) || settings.panels.count + settings.hiddenPanels.count < 32 else { return }
            settings.hiddenPanels.removeAll { $0.id == panel.id }
            settings.panels.append(existing)
        } else {
            guard !settings.hiddenPanels.contains(where: { $0.id == panel.id }) else { return }
            let existing = settings.panels.first { $0.id == panel.id } ?? panel
            guard settings.panels.contains(where: { $0.id == panel.id }) || settings.panels.count + settings.hiddenPanels.count < 32 else { return }
            settings.panels.removeAll { $0.id == panel.id }
            settings.hiddenPanels.append(existing)
        }
    }

    public static func setPanel(in settings: inout AppSettings, metric: MetricID, visible: Bool) {
        if visible {
            guard !settings.panels.contains(where: { $0.metric == metric }) else { return }
            let panel = settings.hiddenPanels.first { $0.metric == metric } ?? PanelConfiguration(metric: metric, networkInterface: metric == .upload || metric == .download ? settings.networkInterface : nil, appearance: settings.panelAppearance(for: metric))
            setPanel(in: &settings, panel: panel, visible: true)
        } else {
            for panel in settings.panels.filter({ $0.metric == metric }) { setPanel(in: &settings, panel: panel, visible: false) }
        }
    }
}
