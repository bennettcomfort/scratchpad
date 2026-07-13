import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    private(set) var current: EditorTheme = .scratchDark

    private let defaults = UserDefaults.standard
    private let key = "editor_theme_name"

    init() {
        if let name = defaults.string(forKey: key),
           let theme = EditorTheme.all.first(where: { $0.name == name }) {
            current = theme
        }
    }

    func select(_ theme: EditorTheme) {
        current = theme
        defaults.set(theme.name, forKey: key)
    }
}
