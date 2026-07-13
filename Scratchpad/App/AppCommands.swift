import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Scratch Buffer") { model.newScratchBuffer() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("Open…") { model.openFile() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Save") { model.saveFile() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save As…") { model.saveFileAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) { }
    }
}
