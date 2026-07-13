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
            Divider()
            Button("Close Tab") { model.closeActiveTab() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Next Tab") { model.nextTab() }
                .keyboardShortcut("}", modifiers: .command)
            Button("Previous Tab") { model.previousTab() }
                .keyboardShortcut("{", modifiers: .command)
            Divider()
            Button("Open Folder…") { model.openFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
                .keyboardShortcut("\\", modifiers: .command)
            Divider()
            Button("Quick Open…") {
                NotificationCenter.default.post(name: .showQuickSwitcher, object: nil)
            }
                .keyboardShortcut("p", modifiers: .command)
        }
        CommandGroup(replacing: .printItem) { }
    }
}
