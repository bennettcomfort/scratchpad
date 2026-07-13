import SwiftUI

@main
struct ScratchpadApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("Scratchpad", id: "main") {
            Text("Scratchpad")
                .frame(minWidth: 480, minHeight: 320)
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands(model: model) }
    }
}
