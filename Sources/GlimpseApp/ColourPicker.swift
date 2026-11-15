import AppKit
import SwiftUI
import GlimpseCore

/// Preset swatches followed by a rainbow-ringed swatch that opens the
/// system colour panel; the ring shows the current colour.
struct PaletteColourPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: MeterColour
    /// The title stays as the accessibility label when hidden.
    var showsTitle = true

    var body: some View {
        HStack(spacing: 6) {
            if showsTitle { Text(title).fixedSize() }
            ForEach(MeterColour.allCases) { colour in
                Button { selection = colour } label: {
                    Circle().fill(Color(colour.nsColor))
                        .frame(width: 18, height: 18)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selection == colour ? Color.primary : Color.clear, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(colour.title)
                .accessibilityLabel("\(title): \(colour.title)")
                .accessibilityAddTraits(selection == colour ? .isSelected : [])
            }
            Button { ColourPanel.shared.open(selection.nsColor) { selection = $0 } } label: {
                Circle().fill(Color(selection.nsColor))
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .background(Circle().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1))
                    .padding(2)
                    .background(Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Custom colour…")
            .accessibilityLabel("\(title): custom colour")
        }
    }
}

/// Routes the shared NSColorPanel to whichever swatch opened it last.
private final class ColourPanel: NSObject {
    static let shared = ColourPanel()
    private var onChange: ((MeterColour) -> Void)?

    func open(_ colour: NSColor, onChange: @escaping (MeterColour) -> Void) {
        self.onChange = nil
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = colour
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        onChange?(.custom(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)))
    }
}
