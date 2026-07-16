import AppKit
import SwiftUI

enum GeneralSettingsControl: String, Equatable {
    case launchAtLogin
    case openRecoveryFolder
}

struct GeneralSettingsPresentation {
    static let controls: [GeneralSettingsControl] = [.launchAtLogin, .openRecoveryFolder]
    static let deferredControls: [String] = []
}

enum EditorSettingsControl: String, Equatable {
    case chooseFont
    case smartSubstitutions
    case spellingAndCorrection
    case spacesInsteadOfTabs
    case tabWidth
    case keepIndentation
    case countWhitespace
    case informationBar
}

struct EditorSettingsPresentation {
    static let controls: [EditorSettingsControl] = [
        .chooseFont,
        .smartSubstitutions,
        .spellingAndCorrection,
        .spacesInsteadOfTabs,
        .tabWidth,
        .keepIndentation,
        .countWhitespace,
        .informationBar,
    ]
    static let tabWidthRange = 1...8
    static let deferredControls: [String] = []
}

struct ThemeSettingsPresentation {
    static let appearances: [AppearancePreference] = [.system, .light, .dark]
    static let isPreviewEditable = false
    static let deferredControls: [String] = []
}

struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    let recoveryFolder: URL
    @State private var fontPanelCoordinator: FontPanelCoordinator

    init(settings: SettingsStore, recoveryFolder: URL) {
        self.settings = settings
        self.recoveryFolder = recoveryFolder
        _fontPanelCoordinator = State(
            initialValue: FontPanelCoordinator(settings: settings)
        )
    }

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }
            editorSettings
                .tabItem { Label("Editor", systemImage: "textformat") }
            themeSettings
                .tabItem { Label("Theme", systemImage: "circle.lefthalf.filled") }
        }
        .frame(width: 520, height: 390)
        .onDisappear { fontPanelCoordinator.close() }
    }

    private var generalSettings: some View {
        Form {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                )
            )
            Button("Open Recovery Folder") {
                _ = NSWorkspace.shared.open(recoveryFolder)
            }
            if let errorMessage = settings.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var editorSettings: some View {
        Form {
            LabeledContent("Font") {
                Button("Choose Font") { fontPanelCoordinator.open() }
            }
            Toggle(
                "Smart substitutions",
                isOn: Binding(
                    get: { settings.snapshot.smartSubstitutionsEnabled },
                    set: { settings.setSmartSubstitutionsEnabled($0) }
                )
            )
            Toggle(
                "Spelling checking and correction",
                isOn: Binding(
                    get: { settings.snapshot.spellingEnabled },
                    set: { settings.setSpellingEnabled($0) }
                )
            )
            Toggle(
                "Insert spaces instead of tabs",
                isOn: Binding(
                    get: { settings.snapshot.insertsSpaces },
                    set: { settings.setInsertsSpaces($0) }
                )
            )
            Stepper(
                "Tab width: \(settings.snapshot.tabWidth)",
                value: Binding(
                    get: { settings.snapshot.tabWidth },
                    set: { settings.setTabWidth($0) }
                ),
                in: EditorSettingsPresentation.tabWidthRange
            )
            Toggle(
                "Keep indentation on new lines",
                isOn: Binding(
                    get: { settings.snapshot.keepsIndentation },
                    set: { settings.setKeepsIndentation($0) }
                )
            )
            Toggle(
                "Count whitespace in characters",
                isOn: Binding(
                    get: { settings.snapshot.countsWhitespace },
                    set: { settings.setCountsWhitespace($0) }
                )
            )
            Toggle(
                "Information bar",
                isOn: Binding(
                    get: { settings.snapshot.showsInformationBar },
                    set: { settings.setShowsInformationBar($0) }
                )
            )
        }
        .formStyle(.grouped)
        .padding()
    }

    private var themeSettings: some View {
        Form {
            Picker(
                "Appearance",
                selection: Binding(
                    get: { settings.snapshot.appearance },
                    set: { settings.setAppearance($0) }
                )
            ) {
                Text("System").tag(AppearancePreference.system)
                Text("Light").tag(AppearancePreference.light)
                Text("Dark").tag(AppearancePreference.dark)
            }
            .pickerStyle(.segmented)

            ThemePreviewView(settings: settings.snapshot)
        }
        .formStyle(.grouped)
        .padding()
    }

}
