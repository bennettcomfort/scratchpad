import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("escAlsoCopies") private var escAlsoCopies = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
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
        .padding(20)
        .frame(width: 420)
    }
}
