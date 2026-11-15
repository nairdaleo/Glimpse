import SwiftUI
import GlimpseCore

struct StatusPanel: View {
    @ObservedObject var store: MonitoringStore
    var showSettings: () -> Void
    var editCard: (UUID) -> Void
    var maximumSize: CGSize

    init(store: MonitoringStore, showSettings: @escaping () -> Void, editCard: @escaping (UUID) -> Void,
         maximumSize: CGSize = CGSize(width: 1600, height: 1000)) {
        self.store = store
        self.showSettings = showSettings
        self.editCard = editCard
        self.maximumSize = maximumSize
    }

    var body: some View {
        let layout = StatusPanelLayout(settings: store.settings, maximumSize: maximumSize)
        VStack(spacing: 0) {
            header.frame(height: StatusPanelLayout.headerHeight)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if store.settings.panels.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No detail panels added.").font(.callout)
                            Button("Choose panels…", action: showSettings).font(.caption)
                        }.frame(width: layout.gridWidth, height: layout.gridHeight, alignment: .leading)
                    } else {
                        ZStack(alignment: .topLeading) {
                            ForEach(store.settings.panels) { panel in
                                if let placement = layout.placements[panel.id] {
                                    // A tap target rather than a Button, so values inside the card (click to copy)
                                    // receive their own clicks first; VoiceOver still sees a button.
                                    MetricCardContent(panel: panel, snapshot: store.snapshot, history: store.history,
                                                      networkHistory: store.networkHistory, settings: store.settings,
                                                      width: placement.width, height: placement.height)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editCard(panel.id) }
                                        .accessibilityElement(children: .contain)
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { editCard(panel.id) }
                                        .accessibilityHint("Opens settings for this panel")
                                        .help("Edit \(panel.displayTitle) panel settings")
                                        .offset(x: placement.minX, y: placement.minY)
                                }
                            }
                        }.frame(width: layout.gridWidth, height: layout.gridHeight, alignment: .topLeading)
                    }
                }.padding(StatusPanelLayout.padding)
            }
            Divider()
            HStack {
                Button(action: showSettings) { Image(systemName: "gearshape").frame(width: 22, height: 20) }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings… (⌘,)").accessibilityLabel("Settings")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 14)
                .frame(height: StatusPanelLayout.footerHeight)
        }.frame(width: layout.size.width, height: layout.size.height)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 12)).foregroundColor(.accentColor)
            Text("Glimpse").font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let age = max(0, Int(ProcessInfo.processInfo.systemUptime - store.snapshot.timestamp))
                let stale = Double(age) > max(10, store.settings.refreshInterval * 3)
                Label("\(stale ? "Paused" : "Live") · \(age)s", systemImage: stale ? "pause.circle.fill" : "circle.fill")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(stale ? .orange : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }.padding(.horizontal, 14)
    }
}

