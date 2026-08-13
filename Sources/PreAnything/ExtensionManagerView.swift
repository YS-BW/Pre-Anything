import AppKit
import SwiftUI

struct ExtensionManagerView: View {
    private let formats = [
        FormatSummary(icon: "text.document", name: "Markdown", detail: "Rendered document preview"),
        FormatSummary(icon: "curlybraces", name: "JSON", detail: "Faithful formatting and syntax highlighting"),
        FormatSummary(icon: "list.bullet.indent", name: "YAML", detail: "Original source with syntax highlighting"),
    ]

    @State private var showNavigationHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Pre-Anything")
                    .font(.largeTitle.weight(.semibold))

                Text("Choose which native Quick Look previews macOS should use.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(formats) { format in
                    HStack(spacing: 14) {
                        Image(systemName: format.icon)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.name).fontWeight(.medium)
                            Text(format.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)

                    if format.id != formats.last?.id {
                        Divider()
                    }
                }
            }

            Spacer(minLength: 8)

            HStack {
                Text("Extensions are enabled and disabled by macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Manage Quick Look Extensions") {
                    openExtensionSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .alert("Open System Settings", isPresented: $showNavigationHelp) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Open General → Login Items & Extensions → Quick Look to manage Markdown, JSON, and YAML previews.")
        }
    }

    private func openExtensionSettings() {
        // macOS doesn't expose a public API for changing Quick Look activation.
        // This URL opens the public System Settings application at its extensions area when supported.
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }

        showNavigationHelp = true
    }
}

private struct FormatSummary: Identifiable {
    let icon: String
    let name: String
    let detail: String

    var id: String { name }
}
