import AppKit
import SwiftUI

/// Build details, licences, support and links. The direct-download build
/// supports development through Ko-fi; the Mac App Store build uses in-app
/// purchase tips instead (external payment links are not allowed there).
struct AboutView: View {
    private let info = Bundle.main.infoDictionary ?? [:]
    private var version: String { info["CFBundleShortVersionString"] as? String ?? "development" }
    private var build: String { info["CFBundleVersion"] as? String ?? "—" }
    private var commit: String { info["GlimpseCommit"] as? String ?? "—" }
    private var architecture: String {
        #if arch(arm64)
        return String(localized: "Apple silicon")
        #else
        return "Intel"
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 28)).foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Glimpse").font(.title2.weight(.semibold))
                        Text("Version \(version) (\(build))").foregroundColor(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    row("Commit", commit)
                    row("Running on", "\(architecture) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                    Button("Copy build information") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("Glimpse \(version) (\(build), \(commit)) on \(architecture), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", forType: .string)
                    }.font(.caption)
                }
                Divider()
                Text("Support").font(.headline)
                #if APP_STORE
                Text("Glimpse is free, with every feature included. If it is useful to you, a tip helps keep it going.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                TipJarView()
                Link("More apps by Tasty Jam", destination: URL(string: "https://tastyjam.ca")!)
                #else
                Text("Glimpse is free and open source. If it is useful to you, a coffee helps keep it going.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Link(destination: URL(string: "https://ko-fi.com/tastyjam")!) {
                        Label("Support on Ko-fi", systemImage: "cup.and.saucer.fill")
                    }.buttonStyle(.borderedProminent)
                    Link("More apps by Tasty Jam", destination: URL(string: "https://tastyjam.ca")!)
                }
                #endif
                HStack(spacing: 16) {
                    Link("Contact Support", destination: URL(string: "mailto:support@tastyjam.ca?subject=Glimpse%20Support")!)
                    Link("Source code on GitHub", destination: URL(string: "https://github.com/nairdaleo/Glimpse")!)
                }.font(.callout)
                HStack(spacing: 16) {
                    Link("Privacy Policy", destination: URL(string: "https://tastyjam.ca/glimpse/privacy.html")!)
                    Link("Terms of Use", destination: URL(string: "https://tastyjam.ca/glimpse/terms.html")!)
                }.font(.callout)
                Divider()
                Text("Licences").font(.headline)
                HStack(spacing: 16) {
                    licence("Glimpse (MIT)", file: "LICENSE")
                    licence("Sparkle (MIT)", file: "Sparkle-LICENSE")
                }.font(.callout)
                Spacer(minLength: 8)
                Text("Made with 💜 in BC by Tasty Jam App Development.")
                    .font(.caption).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text(value).textSelection(.enabled)
        }.font(.callout)
    }

    /// Opens a bundled licence file; hidden in development builds without one.
    @ViewBuilder
    private func licence(_ title: String, file: String) -> some View {
        if let url = Bundle.main.url(forResource: file, withExtension: nil) {
            Button(title) { NSWorkspace.shared.open(url) }.buttonStyle(.link)
        }
    }
}
