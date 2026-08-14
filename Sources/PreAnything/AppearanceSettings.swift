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

    @Published var sourceCodeTransparent: Bool {
        didSet { preferences.setTransparent(sourceCodeTransparent, for: .sourceCode) }
    }

    private let preferences: PreviewAppearancePreferences

    init(preferences: PreviewAppearancePreferences = .shared) {
        self.preferences = preferences
        markdownTransparent = preferences.isTransparent(for: .markdown)
        jsonTransparent = preferences.isTransparent(for: .json)
        yamlTransparent = preferences.isTransparent(for: .yaml)
        sourceCodeTransparent = preferences.isTransparent(for: .sourceCode)
    }

    var allTransparent: Bool {
        markdownTransparent && jsonTransparent && yamlTransparent && sourceCodeTransparent
    }

    func setAllTransparent(_ isTransparent: Bool) {
        markdownTransparent = isTransparent
        jsonTransparent = isTransparent
        yamlTransparent = isTransparent
        sourceCodeTransparent = isTransparent
    }
}
