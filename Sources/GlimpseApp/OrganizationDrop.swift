import AppKit
import SwiftUI
import GlimpseCore

enum OrganizationDragPayload: Equatable {
    enum Kind {
        case column, panel
        var pasteboardType: NSPasteboard.PasteboardType {
            NSPasteboard.PasteboardType("com.tastyjam.glimpse.organizer.\(self == .column ? "column" : "panel")")
        }
    }
    case column(UUID)
    case panel(MetricID)

    var kind: Kind {
        switch self { case .column: return .column; case .panel: return .panel }
    }
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
    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: kind.pasteboardType)
        return item
    }
    static func read(from board: NSPasteboard, kind: Kind) -> Self? {
        board.string(forType: kind.pasteboardType).flatMap { Self(text: $0, kind: kind) }
    }
}

enum OrganizationDropEdge { case before, after }

enum OrganizationDrop {
    /// Resolve the marked edge against the current order; only a completed drop mutates settings.
    @discardableResult
    static func apply(_ payload: OrganizationDragPayload, target: OrganizationDragPayload?, edge: OrganizationDropEdge,
                      settings: inout AppSettings) -> Bool {
        guard payload != target else { return false }
        switch payload {
        case .column(let id):
            var before: UUID?
            if let target {
                guard case .column(let targetID) = target,
                      let index = settings.columns.firstIndex(where: { $0.id == targetID }) else { return false }
                before = edge == .before ? targetID : settings.columns.dropFirst(index + 1).first?.id
            }
            return WidgetOrganization.moveColumn(in: &settings, id: id, before: before)
        case .panel(let metric):
            var before: MetricID?
            if let target {
                guard case .panel(let targetMetric) = target,
                      let index = settings.panelMetrics.firstIndex(of: targetMetric) else { return false }
                before = edge == .before ? targetMetric : settings.panelMetrics.dropFirst(index + 1).first
            }
            return WidgetOrganization.movePanel(in: &settings, metric: metric, before: before)
        }
    }
}

/// Native drag sessions give us a real preview and an end callback even when Escape cancels
/// or the pointer leaves the window. Click selection and dragging share one hit target.
struct OrganizationTile<Content: View>: NSViewRepresentable {
    let payload: OrganizationDragPayload?
    let kind: OrganizationDragPayload.Kind
    var isSelected = false
    let label: String
    let select: () -> Void
    let drop: (OrganizationDragPayload, OrganizationDropEdge) -> Bool
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> OrganizationTileView<Content> {
        OrganizationTileView(content: content())
    }
    func updateNSView(_ view: OrganizationTileView<Content>, context: Context) {
        view.content = content()
        view.payload = payload
        view.kind = kind
        view.select = select
        view.drop = drop
        view.setAccessibilityLabel(label)
        view.setAccessibilitySelected(isSelected)
        view.registerForDraggedTypes([kind.pasteboardType])
        view.refreshAppearance()
    }
}

final class OrganizationTileView<Content: View>: NSView, NSDraggingSource {
    var content: Content
    var payload: OrganizationDragPayload?
    var kind: OrganizationDragPayload.Kind = .column
    var select: () -> Void = {}
    var drop: (OrganizationDragPayload, OrganizationDropEdge) -> Bool = { _, _ in false }
    private let hosting: NSHostingView<AnyView>
    private var pressedAt: NSPoint?
    private var isDragging = false
    private var edge: OrganizationDropEdge?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { payload != nil }

    init(content: Content) {
        self.content = content
        hosting = NSHostingView(rootView: AnyView(content))
        super.init(frame: .zero)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func resetCursorRects() {
        if payload != nil { addCursorRect(bounds, cursor: .openHand) }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pressedAt = convert(event.locationInWindow, from: nil)
    }
    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil }
        if pressedAt != nil, !isDragging, bounds.contains(convert(event.locationInWindow, from: nil)) { select() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { select() } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { select(); return true }
    override func mouseDragged(with event: NSEvent) {
        guard let pressedAt, let payload, !isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - pressedAt.x, point.y - pressedAt.y) >= 4,
              let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let preview = NSImage(size: bounds.size)
        preview.addRepresentation(bitmap)
        let item = NSDraggingItem(pasteboardWriter: payload.pasteboardItem)
        item.setDraggingFrame(bounds, contents: preview)
        isDragging = true
        refreshAppearance()
        beginDraggingSession(with: [item], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        pressedAt = nil
        edge = nil
        refreshAppearance()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDestination(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDestination(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { clearDestination() }
    override func draggingEnded(_ sender: NSDraggingInfo) { clearDestination() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedPayload(sender) != nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearDestination() }
        guard let incoming = acceptedPayload(sender) else { return false }
        return drop(incoming, destinationEdge(sender))
    }
    private func acceptedPayload(_ sender: NSDraggingInfo) -> OrganizationDragPayload? {
        guard let incoming = OrganizationDragPayload.read(from: sender.draggingPasteboard, kind: kind), incoming != payload else { return nil }
        return incoming
    }
    private func destinationEdge(_ sender: NSDraggingInfo) -> OrganizationDropEdge {
        payload == nil || convert(sender.draggingLocation, from: nil).x >= bounds.midX ? .after : .before
    }
    private func updateDestination(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptedPayload(sender) != nil else { clearDestination(); return [] }
        if let event = NSApp.currentEvent { _ = autoscroll(with: event) }
        edge = destinationEdge(sender)
        refreshAppearance()
        return .move
    }
    private func clearDestination() { edge = nil; refreshAppearance() }
    func refreshAppearance() {
        hosting.rootView = AnyView(content
            .opacity(isDragging ? 0.35 : 1)
            .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(edge == nil ? 0 : 0.12)))
            .overlay(alignment: edge == .before ? .leading : .trailing) {
                if edge != nil {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 4).padding(.vertical, 4)
                }
            })
    }
}
