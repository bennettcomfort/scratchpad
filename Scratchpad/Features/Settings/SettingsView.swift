import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("escAlsoCopies") private var escAlsoCopies = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                Picker("Editor theme", selection: Binding(
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
            }
            .tabItem { Label("Appearance", systemImage: "paintpalette") }
            .padding(20)
        }
        .frame(width: 420, height: 220)
    }
}
