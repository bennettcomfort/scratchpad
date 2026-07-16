import AppKit

@MainActor
struct ThemeDefinition: Equatable {
    let editorBackground: NSColor
    let editorForeground: NSColor
    let caret: NSColor
    let selection: NSColor
    let titleRegion: NSColor
    let separator: NSColor
    let informationBar: NSColor
    let mutedText: NSColor
    let banner: NSColor

    static func resolve(
        _ preference: AppearancePreference,
        effectiveAppearance: NSAppearance
    ) -> Self {
        let resolvedPreference: AppearancePreference
        switch preference {
        case .system:
            resolvedPreference = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .dark
                : .light
        case .light, .dark:
            resolvedPreference = preference
        }

        switch resolvedPreference {
        case .light:
            return definition(
                appearanceName: .aqua,
                editorBackground: 0xFBFBFC,
                editorForeground: 0x171717,
                titleRegion: 0xF8F7FA,
                separator: 0xD8D8DC,
                informationBar: 0xF4F4F5,
                mutedText: 0x6F6F73,
                banner: 0xFFF3CD
            )
        case .dark:
            return definition(
                appearanceName: .darkAqua,
                editorBackground: 0x2B2B2B,
                editorForeground: 0xE7E7E7,
                titleRegion: 0x2B2B2B,
                separator: 0x414141,
                informationBar: 0x252525,
                mutedText: 0xA2A2A2,
                banner: 0x4A3D20
            )
        case .system:
            preconditionFailure("System appearance must resolve to a fixed palette")
        }
    }

    private static func definition(
        appearanceName: NSAppearance.Name,
        editorBackground: Int,
        editorForeground: Int,
        titleRegion: Int,
        separator: Int,
        informationBar: Int,
        mutedText: Int,
        banner: Int
    ) -> Self {
        guard let appearance = NSAppearance(named: appearanceName) else {
            preconditionFailure("Required native appearance is unavailable")
        }
        let selection = resolvedSystemColor(.selectedTextBackgroundColor, appearance: appearance)
        let foreground = deviceColor(editorForeground)
        return Self(
            editorBackground: deviceColor(editorBackground),
            editorForeground: foreground,
            caret: foreground,
            selection: selection,
            titleRegion: deviceColor(titleRegion),
            separator: deviceColor(separator),
            informationBar: deviceColor(informationBar),
            mutedText: deviceColor(mutedText),
            banner: deviceColor(banner)
        )
    }

    fileprivate static func resolvedSelectionForeground(
        for preference: AppearancePreference,
        effectiveAppearance: NSAppearance
    ) -> NSColor {
        let appearanceName: NSAppearance.Name
        switch preference {
        case .system:
            appearanceName = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? .darkAqua
                : .aqua
        case .light:
            appearanceName = .aqua
        case .dark:
            appearanceName = .darkAqua
        }
        guard let appearance = NSAppearance(named: appearanceName) else {
            preconditionFailure("Required native appearance is unavailable")
        }
        return resolvedSystemColor(.selectedTextColor, appearance: appearance)
    }

    private static func resolvedSystemColor(
        _ color: NSColor,
        appearance: NSAppearance
    ) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

    private static func deviceColor(_ hex: Int) -> NSColor {
        NSColor(
            deviceRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

@MainActor
struct ResolvedEditorStyle {
    let theme: ThemeDefinition
    let selectionForeground: NSColor
    let font: NSFont
    let smartSubstitutionsEnabled: Bool
    let spellingEnabled: Bool
    let insertsSpaces: Bool
    let tabWidth: Int
    let keepsIndentation: Bool

    init(settings: EditorSettingsSnapshot, effectiveAppearance: NSAppearance) {
        theme = ThemeDefinition.resolve(
            settings.appearance,
            effectiveAppearance: effectiveAppearance
        )
        selectionForeground = ThemeDefinition.resolvedSelectionForeground(
            for: settings.appearance,
            effectiveAppearance: effectiveAppearance
        )
        font = Self.resolveFont(settings.font)
        smartSubstitutionsEnabled = settings.smartSubstitutionsEnabled
        spellingEnabled = settings.spellingEnabled
        insertsSpaces = settings.insertsSpaces
        tabWidth = min(max(settings.tabWidth, 1), 8)
        keepsIndentation = settings.keepsIndentation
    }

    private static func resolveFont(_ preference: FontPreference) -> NSFont {
        if preference.pointSize > 0,
           let font = NSFont(
               name: preference.postScriptName,
               size: preference.pointSize
           ) {
            return font
        }
        return NSFont(name: "SFMono-Regular", size: 15)
            ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    }
}

extension EditorSettingsSnapshot {
    static let editorDefaults = Self(
        font: FontPreference(postScriptName: "SFMono-Regular", pointSize: 15),
        smartSubstitutionsEnabled: false,
        spellingEnabled: false,
        insertsSpaces: false,
        tabWidth: 4,
        keepsIndentation: true,
        countsWhitespace: false,
        showsInformationBar: true,
        appearance: .system
    )
}
