import SwiftUI

@main
struct ScratchpadApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("Scratchpad", id: "main") {
            MainWindowView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(model: model) }
    }
}
