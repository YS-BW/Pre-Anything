import Combine
import PreviewKit

@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var markdownTransparent: Bool {
        didSet { preferences.setTransparent(markdownTransparent, for: .markdown) }
    }

    @Published var jsonTransparent: Bool {
        didSet { preferences.setTransparent(jsonTransparent, for: .json) }
    }

    @Published var yamlTransparent: Bool {
        didSet { preferences.setTransparent(yamlTransparent, for: .yaml) }
    }

    @Published var configTransparent: Bool {
        didSet { preferences.setTransparent(configTransparent, for: .config) }
    }

    @Published var tableTransparent: Bool {
        didSet { preferences.setTransparent(tableTransparent, for: .table) }
    }

    @Published var xmlTransparent: Bool {
        didSet { preferences.setTransparent(xmlTransparent, for: .xml) }
    }

    @Published var notebookTransparent: Bool {
        didSet { preferences.setTransparent(notebookTransparent, for: .notebook) }
    }

    @Published var sourceCodeTransparent: Bool {
        didSet { preferences.setTransparent(sourceCodeTransparent, for: .sourceCode) }
    }

    private let preferences: PreviewAppearancePreferences

    init(preferences: PreviewAppearancePreferences = .shared) {
        self.preferences = preferences
        markdownTransparent = preferences.isTransparent(for: .markdown)
        jsonTransparent = preferences.isTransparent(for: .json)
        yamlTransparent = preferences.isTransparent(for: .yaml)
        configTransparent = preferences.isTransparent(for: .config)
        tableTransparent = preferences.isTransparent(for: .table)
        xmlTransparent = preferences.isTransparent(for: .xml)
        notebookTransparent = preferences.isTransparent(for: .notebook)
        sourceCodeTransparent = preferences.isTransparent(for: .sourceCode)
    }

    var allTransparent: Bool {
        markdownTransparent && jsonTransparent && yamlTransparent && configTransparent
            && tableTransparent && xmlTransparent && notebookTransparent && sourceCodeTransparent
    }

    func setAllTransparent(_ isTransparent: Bool) {
        markdownTransparent = isTransparent
        jsonTransparent = isTransparent
        yamlTransparent = isTransparent
        configTransparent = isTransparent
        tableTransparent = isTransparent
        xmlTransparent = isTransparent
        notebookTransparent = isTransparent
        sourceCodeTransparent = isTransparent
    }
}
