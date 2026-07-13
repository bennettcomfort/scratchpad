import SwiftUI

@main
struct ScratchpadApp: App {
    var body: some Scene {
        Window("Scratchpad", id: "main") {
            Text("Scratchpad")
                .frame(minWidth: 480, minHeight: 320)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
