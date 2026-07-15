import SwiftUI

@main
struct ScratchpadApp: App {
    @State private var model = ApplicationModel()

    var body: some Scene {
        Window("Untitled", id: "main") {
            MainWindowView()
                .environment(model)
        }
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            TextEditingCommands()
        }
    }
}
