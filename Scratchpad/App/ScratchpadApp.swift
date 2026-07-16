import SwiftUI

@main
struct ScratchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ApplicationModel.live()

    var body: some Scene {
        Window("Untitled", id: "main") {
            MainWindowView()
                .environment(model)
                .background(WindowLifecycleInstaller(model: model))
                .onAppear { appDelegate.attach(model: model) }
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            TextEditingCommands()
            AppCommands(model: model)
        }
    }
}
