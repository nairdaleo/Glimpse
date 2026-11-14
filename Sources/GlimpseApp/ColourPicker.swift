import AppKit
import SwiftUI
import GlimpseCore

struct PaletteColourPicker: View {
    let title: String
    @Binding var selection: MeterColour

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColorPicker(title, selection: Binding(get: { Color(selection.nsColor) }, set: { colour in
                guard let rgb = NSColor(colour).usingColorSpace(.sRGB) else { return }
                selection = .custom(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
            }), supportsOpacity: false)
            Text("Suggested colours").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(MeterColour.allCases) { colour in
                    Button { selection = colour } label: {
                        Circle().fill(Color(colour.nsColor))
                            .frame(width: 16, height: 16)
                            .padding(3)
                            .overlay(Circle().strokeBorder(selection == colour ? Color.primary : Color.clear, lineWidth: 1.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(colour.title)
                    .accessibilityLabel("\(title): \(colour.title)")
                    .accessibilityAddTraits(selection == colour ? .isSelected : [])
                }
            }
        }
    }
}
