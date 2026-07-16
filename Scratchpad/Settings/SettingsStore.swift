import AppKit
import Foundation
import Observation

enum AppearancePreference: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

struct FontPreference: Codable, Equatable, Sendable {
    let postScriptName: String
    let pointSize: Double
}

struct EditorSettingsSnapshot: Equatable, Sendable {
    let font: FontPreference
    let smartSubstitutionsEnabled: Bool
    let spellingEnabled: Bool
    let insertsSpaces: Bool
    let tabWidth: Int
    let keepsIndentation: Bool
    let countsWhitespace: Bool
    let showsInformationBar: Bool
    let appearance: AppearancePreference
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
@Observable
final class SettingsStore {
    private(set) var snapshot: EditorSettingsSnapshot
    private(set) var launchAtLogin: Bool
    private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let launchService: any LaunchAtLoginServicing

    init(defaults: UserDefaults, launchService: any LaunchAtLoginServicing) {
        self.defaults = defaults
        self.launchService = launchService
        defaults.register(defaults: Self.registeredDefaults)

        let actualLaunchStatus = launchService.isEnabled
        defaults.set(actualLaunchStatus, forKey: Key.launchAtLogin)
        launchAtLogin = actualLaunchStatus
        errorMessage = nil
        snapshot = Self.makeSnapshot(defaults: defaults)
    }

    static func transient() -> SettingsStore {
        let suiteName = "ApplicationModel.Transient.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return SettingsStore(
                defaults: .standard,
                launchService: TransientLaunchAtLoginService()
            )
        }
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(
            defaults: defaults,
            launchService: TransientLaunchAtLoginService()
        )
        defaults.removePersistentDomain(forName: suiteName)
        return store
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchService.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t update Launch at Login."
        }

        let actualLaunchStatus = launchService.isEnabled
        defaults.set(actualLaunchStatus, forKey: Key.launchAtLogin)
        launchAtLogin = actualLaunchStatus
    }

    func setFont(_ font: FontPreference) {
        if let encoded = try? JSONEncoder().encode(font) {
            defaults.set(encoded, forKey: Key.font)
        }
        rebuildSnapshot()
    }

    func setSmartSubstitutionsEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.smartSubstitutionsEnabled)
        rebuildSnapshot()
    }

    func setSpellingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.spellingEnabled)
        rebuildSnapshot()
    }

    func setInsertsSpaces(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.insertsSpaces)
        rebuildSnapshot()
    }

    func setTabWidth(_ width: Int) {
        defaults.set(min(max(width, 1), 8), forKey: Key.tabWidth)
        rebuildSnapshot()
    }

    func setKeepsIndentation(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.keepsIndentation)
        rebuildSnapshot()
    }

    func setCountsWhitespace(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.countsWhitespace)
        rebuildSnapshot()
    }

    func setShowsInformationBar(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.showsInformationBar)
        rebuildSnapshot()
    }

    func setAppearance(_ appearance: AppearancePreference) {
        defaults.set(appearance.rawValue, forKey: Key.appearance)
        rebuildSnapshot()
    }

    private func rebuildSnapshot() {
        snapshot = Self.makeSnapshot(defaults: defaults)
    }

    private static func makeSnapshot(defaults: UserDefaults) -> EditorSettingsSnapshot {
        let storedFont = defaults.data(forKey: Key.font)
            .flatMap { try? JSONDecoder().decode(FontPreference.self, from: $0) }
        let font = storedFont.flatMap { preference in
            guard preference.pointSize > 0,
                  NSFont(name: preference.postScriptName, size: preference.pointSize) != nil else {
                return nil
            }
            return preference
        } ?? defaultFont

        return EditorSettingsSnapshot(
            font: font,
            smartSubstitutionsEnabled: defaults.bool(forKey: Key.smartSubstitutionsEnabled),
            spellingEnabled: defaults.bool(forKey: Key.spellingEnabled),
            insertsSpaces: defaults.bool(forKey: Key.insertsSpaces),
            tabWidth: min(max(defaults.integer(forKey: Key.tabWidth), 1), 8),
            keepsIndentation: defaults.bool(forKey: Key.keepsIndentation),
            countsWhitespace: defaults.bool(forKey: Key.countsWhitespace),
            showsInformationBar: defaults.bool(forKey: Key.showsInformationBar),
            appearance: AppearancePreference(
                rawValue: defaults.string(forKey: Key.appearance) ?? ""
            ) ?? .system
        )
    }

    private static let defaultFont = FontPreference(postScriptName: "SFMono-Regular", pointSize: 15)

    private static let registeredDefaults: [String: Any] = [
        Key.launchAtLogin: false,
        Key.font: encodedDefaultFont,
        Key.smartSubstitutionsEnabled: false,
        Key.spellingEnabled: false,
        Key.insertsSpaces: false,
        Key.tabWidth: 4,
        Key.keepsIndentation: true,
        Key.countsWhitespace: false,
        Key.showsInformationBar: true,
        Key.appearance: AppearancePreference.system.rawValue,
    ]

    private static let encodedDefaultFont: Data = {
        do {
            return try JSONEncoder().encode(defaultFont)
        } catch {
            return Data()
        }
    }()

    private enum Key {
        static let launchAtLogin = "settings.launchAtLogin"
        static let font = "settings.font"
        static let smartSubstitutionsEnabled = "settings.smartSubstitutionsEnabled"
        static let spellingEnabled = "settings.spellingEnabled"
        static let insertsSpaces = "settings.insertsSpaces"
        static let tabWidth = "settings.tabWidth"
        static let keepsIndentation = "settings.keepsIndentation"
        static let countsWhitespace = "settings.countsWhitespace"
        static let showsInformationBar = "settings.showsInformationBar"
        static let appearance = "settings.appearance"
    }
}

@MainActor
private final class TransientLaunchAtLoginService: LaunchAtLoginServicing {
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
