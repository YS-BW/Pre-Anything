import AppKit
import PreviewKit
import SwiftUI

struct ExtensionManagerView: View {
    private let formats = [
        FormatSummary(
            format: .markdown,
            icon: "text.document",
            name: "Markdown",
            detail: "Rendered document preview"
        ),
        FormatSummary(
            format: .json,
            icon: "curlybraces",
            name: "JSON",
            detail: "Faithful formatting and syntax highlighting"
        ),
        FormatSummary(
            format: .yaml,
            icon: "list.bullet.indent",
            name: "YAML",
            detail: "Original source with syntax highlighting"
        ),
        FormatSummary(
            format: .config,
            icon: "slider.horizontal.3",
            name: "Config",
            detail: "TOML, JSONC/JSON5, dotenv, INI, and properties"
        ),
        FormatSummary(
            format: .table,
            icon: "tablecells",
            name: "Table",
            detail: "CSV and TSV with a native header row"
        ),
        FormatSummary(
            format: .xml,
            icon: "chevron.left.forwardslash.chevron.right",
            name: "XML",
            detail: "Original XML with tag and attribute highlighting"
        ),
        FormatSummary(
            format: .notebook,
            icon: "rectangle.stack",
            name: "Notebook",
            detail: "Safe Jupyter cells, text output, and local images"
        ),
        FormatSummary(
            format: .sourceCode,
            icon: "chevron.left.forwardslash.chevron.right",
            name: "Source Code",
            detail: "Native highlighting with line numbers"
        ),
    ]

    @StateObject private var appearanceSettings = AppearanceSettings()
    @State private var showNavigationHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Pre-Anything")
                    .font(.largeTitle.weight(.semibold))

                Text("Configure the appearance of native Quick Look previews.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transparent Background")
                            .font(.headline)
                        Text("Finder's preview material remains visible behind the content.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("All Formats", isOn: allTransparentBinding)
                        .toggleStyle(.switch)
                }

                Divider()

                ForEach(formats) { format in
                    Toggle(isOn: transparentBinding(for: format.format)) {
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
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 12)

                    if format.id != formats.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

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
            Text("Open General → Login Items & Extensions → Quick Look to manage the eight Pre-Anything preview families.")
        }
    }

    private var allTransparentBinding: Binding<Bool> {
        Binding(
            get: { appearanceSettings.allTransparent },
            set: { appearanceSettings.setAllTransparent($0) }
        )
    }

    private func transparentBinding(for format: PreviewFormat) -> Binding<Bool> {
        switch format {
        case .markdown:
            $appearanceSettings.markdownTransparent
        case .json:
            $appearanceSettings.jsonTransparent
        case .yaml:
            $appearanceSettings.yamlTransparent
        case .config:
            $appearanceSettings.configTransparent
        case .table:
            $appearanceSettings.tableTransparent
        case .xml:
            $appearanceSettings.xmlTransparent
        case .notebook:
            $appearanceSettings.notebookTransparent
        case .sourceCode:
            $appearanceSettings.sourceCodeTransparent
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
    let format: PreviewFormat
    let icon: String
    let name: String
    let detail: String

    var id: String { name }
}
