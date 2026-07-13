import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Scratch Buffer") { model.newScratchBuffer() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) { }   // frees ⌘P for quick switcher (Stage 8)
    }
}
