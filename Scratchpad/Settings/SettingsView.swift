import AppKit
import SwiftUI

enum SettingsTab: String, Hashable {
    case general
    case editor
    case theme

    var title: String {
        switch self {
        case .general: "General"
        case .editor: "Editor"
        case .theme: "Theme"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .editor: "textformat"
        case .theme: "circle.lefthalf.filled"
        }
    }
}

private struct SettingsTabSelectionKey: FocusedValueKey {
    typealias Value = Binding<SettingsTab>
}

extension FocusedValues {
    var settingsTabSelection: Binding<SettingsTab>? {
        get { self[SettingsTabSelectionKey.self] }
        set { self[SettingsTabSelectionKey.self] = newValue }
    }
}

struct SettingsPresentation {
    static let tabs: [SettingsTab] = [.general, .editor, .theme]
}

enum GeneralSettingsControl: String, Hashable {
    case launchAtLogin
    case openRecoveryFolder
}

struct GeneralSettingsPresentation {
    static let controls: [GeneralSettingsControl] = [.launchAtLogin, .openRecoveryFolder]
    static let deferredControls: [String] = []
}

enum EditorSettingsControl: String, Hashable {
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

enum ThemeSettingsControl: String, Hashable {
    case appearance
    case preview
}

struct ThemeSettingsPresentation {
    static let controls: [ThemeSettingsControl] = [.appearance, .preview]
    static let appearances: [AppearancePreference] = [.system, .light, .dark]
    static let isPreviewEditable = false
    static let deferredControls: [String] = []
}

struct SettingsView: View {
    @Bindable private var settings: SettingsStore
    let recoveryFolder: URL
    @State private var fontPanelCoordinator: FontPanelCoordinator
    @State private var selectedTab: SettingsTab = .general

    init(settings: SettingsStore, recoveryFolder: URL) {
        self.settings = settings
        self.recoveryFolder = recoveryFolder
        _fontPanelCoordinator = State(
            initialValue: FontPanelCoordinator(settings: settings)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsPresentation.tabs, id: \.self) { tab in
                settingsTab(tab)
                    .tag(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbolName)
                            .accessibilityIdentifier("settings-\(tab.rawValue)")
                            .accessibilityLabel(tab.title)
                    }
            }
        }
        .frame(width: 520, height: 390)
        .focusedSceneValue(\.settingsTabSelection, $selectedTab)
        .onDisappear { fontPanelCoordinator.close() }
    }

    private var generalSettings: some View {
        Form {
            ForEach(GeneralSettingsPresentation.controls, id: \.self) { control in
                generalControl(control)
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
            ForEach(EditorSettingsPresentation.controls, id: \.self) { control in
                editorControl(control)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var themeSettings: some View {
        Form {
            ForEach(ThemeSettingsPresentation.controls, id: \.self) { control in
                themeControl(control)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func settingsTab(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: generalSettings
        case .editor: editorSettings
        case .theme: themeSettings
        }
    }

    @ViewBuilder
    private func generalControl(_ control: GeneralSettingsControl) -> some View {
        switch control {
        case .launchAtLogin:
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                )
            )
            .accessibilityIdentifier("settings-launch-at-login")
        case .openRecoveryFolder:
            Button("Open Recovery Folder") {
                _ = NSWorkspace.shared.open(recoveryFolder)
            }
            .accessibilityIdentifier("settings-open-recovery-folder")
        }
    }

    @ViewBuilder
    private func editorControl(_ control: EditorSettingsControl) -> some View {
        switch control {
        case .chooseFont:
            LabeledContent("Font") {
                Button("Choose Font") { fontPanelCoordinator.open() }
                    .accessibilityIdentifier("settings-choose-font")
            }
        case .smartSubstitutions:
            Toggle(
                "Smart substitutions",
                isOn: Binding(
                    get: { settings.snapshot.smartSubstitutionsEnabled },
                    set: { settings.setSmartSubstitutionsEnabled($0) }
                )
            )
            .accessibilityIdentifier("settings-smart-substitutions")
        case .spellingAndCorrection:
            Toggle(
                "Spelling checking and correction",
                isOn: Binding(
                    get: { settings.snapshot.spellingEnabled },
                    set: { settings.setSpellingEnabled($0) }
                )
            )
            .accessibilityIdentifier("settings-spelling-and-correction")
        case .spacesInsteadOfTabs:
            Toggle(
                "Insert spaces instead of tabs",
                isOn: Binding(
                    get: { settings.snapshot.insertsSpaces },
                    set: { settings.setInsertsSpaces($0) }
                )
            )
            .accessibilityIdentifier("settings-spaces-instead-of-tabs")
        case .tabWidth:
            Stepper(
                "Tab width: \(settings.snapshot.tabWidth)",
                value: Binding(
                    get: { settings.snapshot.tabWidth },
                    set: { settings.setTabWidth($0) }
                ),
                in: EditorSettingsPresentation.tabWidthRange
            )
            .accessibilityIdentifier("settings-tab-width")
        case .keepIndentation:
            Toggle(
                "Keep indentation on new lines",
                isOn: Binding(
                    get: { settings.snapshot.keepsIndentation },
                    set: { settings.setKeepsIndentation($0) }
                )
            )
            .accessibilityIdentifier("settings-keep-indentation")
        case .countWhitespace:
            Toggle(
                "Count whitespace in characters",
                isOn: Binding(
                    get: { settings.snapshot.countsWhitespace },
                    set: { settings.setCountsWhitespace($0) }
                )
            )
            .accessibilityIdentifier("settings-count-whitespace")
        case .informationBar:
            Toggle(
                "Information bar",
                isOn: Binding(
                    get: { settings.snapshot.showsInformationBar },
                    set: { settings.setShowsInformationBar($0) }
                )
            )
            .accessibilityIdentifier("settings-information-bar")
        }
    }

    @ViewBuilder
    private func themeControl(_ control: ThemeSettingsControl) -> some View {
        switch control {
        case .appearance:
            Picker(
                "Appearance",
                selection: Binding(
                    get: { settings.snapshot.appearance },
                    set: { settings.setAppearance($0) }
                )
            ) {
                ForEach(ThemeSettingsPresentation.appearances, id: \.self) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings-appearance")
        case .preview:
            ThemePreviewView(settings: settings.snapshot)
                .accessibilityIdentifier("settings-preview")
        }
    }
}

private extension AppearancePreference {
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
