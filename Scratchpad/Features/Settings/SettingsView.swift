import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("escAlsoCopies") private var escAlsoCopies = false
    @AppStorage("editorFontSize") private var fontSize = 14.0
    @AppStorage("editorFontFamily") private var fontFamily = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !$0.isEmpty }
            .sorted()
    }

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enable in
                        do {
                            if enable { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            Log.logger("settings").error("login item: \(error, privacy: .public)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Esc also copies zen buffer to clipboard", isOn: $escAlsoCopies)
            }
            .tabItem { Label("General", systemImage: "gearshape") }
            .padding(20)

            Form {
                Section("Editor Style") {
                    Stepper(value: $fontSize, in: 8...72, step: 1) {
                        Text("Font size: \(Int(fontSize)) pt")
                    }

                    Picker("Font family", selection: $fontFamily) {
                        Text("System Monospace").tag("")
                        Divider()
                        ForEach(availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Theme", selection: Binding(
                        get: { model.themeManager.current.name },
                        set: { name in
                            if let t = EditorTheme.all.first(where: { $0.name == name }) {
                                model.themeManager.select(t)
                            }
                        }
                    )) {
                        ForEach(EditorTheme.all, id: \.name) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .tabItem { Label("Appearance", systemImage: "paintpalette") }
            .padding(20)
        }
        .frame(width: 420, height: 260)
    }
}
