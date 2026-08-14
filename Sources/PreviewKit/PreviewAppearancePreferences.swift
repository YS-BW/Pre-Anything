import Foundation

/// Shared appearance preferences used by the containing App and every preview extension.
///
/// A missing value intentionally means `true`, preserving the product's transparent
/// background behavior for existing installs and for previews created before the App
/// has ever been launched.
public struct PreviewAppearancePreferences: @unchecked Sendable {
    private static let appGroupInfoKey = "PreAnythingAppGroupIdentifier"

    /// The identifier is injected into every bundle's Info.plist from the
    /// current signing team's build settings. A Team-ID-prefixed group works
    /// on macOS without an embedded provisioning profile.
    public static var appGroupIdentifier: String? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !identifier.isEmpty,
              !identifier.contains("$(") else {
            return nil
        }
        return identifier
    }

    public static var shared: PreviewAppearancePreferences {
        let defaults = appGroupIdentifier.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        return PreviewAppearancePreferences(defaults: defaults)
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func isTransparent(for format: PreviewFormat) -> Bool {
        let key = key(for: format)
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }

    public func setTransparent(_ isTransparent: Bool, for format: PreviewFormat) {
        defaults.set(isTransparent, forKey: key(for: format))
    }

    private func key(for format: PreviewFormat) -> String {
        "preview.background.transparent.\(format.rawValue)"
    }
}
