import SwiftUI

/// A theme bundles the whole visual identity of the app: a `Palette` for each
/// time of day, the procedural scene drawn behind everything, and the
/// dissolution effect played when a poem is released. Adding a theme means
/// conforming this protocol and listing it in `Themes.all`; swapping the active
/// theme (via the dev toggle or `SW_FORCE_THEME`) changes the entire look —
/// scene, colors, and dissolution together.
protocol SceneTheme {
    /// Stable id (used by `SW_FORCE_THEME` and the dev toggle).
    var id: String { get }
    /// Short display name (shown on the dev chip).
    var name: String { get }
    /// Colors for a given time of day.
    func palette(_ timeOfDay: TimeOfDay) -> Palette
    /// The scene drawn behind everything, for a given time of day + palette.
    func background(_ timeOfDay: TimeOfDay, _ palette: Palette) -> AnyView
    /// How a finished poem dissolves under this theme.
    var dissolution: any DissolutionEffect { get }
}

/// The registry of available themes. The first is the default.
enum Themes {
    static let all: [any SceneTheme] = [NatureTheme(), SciFiTheme(), FantasyTheme()]
    static var `default`: any SceneTheme { all[0] }

    static func with(id: String?) -> any SceneTheme {
        guard let id, let match = all.first(where: { $0.id == id }) else { return `default` }
        return match
    }

    /// The next theme in the list, for the dev toggle to cycle through.
    static func after(_ theme: any SceneTheme) -> any SceneTheme {
        guard let i = all.firstIndex(where: { $0.id == theme.id }) else { return `default` }
        return all[(i + 1) % all.count]
    }
}

// MARK: - Environment plumbing

private struct SceneThemeKey: EnvironmentKey {
    static let defaultValue: any SceneTheme = Themes.default
}
extension EnvironmentValues {
    var sceneTheme: any SceneTheme {
        get { self[SceneThemeKey.self] }
        set { self[SceneThemeKey.self] = newValue }
    }
}
