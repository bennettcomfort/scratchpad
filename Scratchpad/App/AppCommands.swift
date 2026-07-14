import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    @AppStorage("sidebarVisible") private var sidebarVisible = false
    @AppStorage("showQuickSwitcher") private var showQuickSwitcher = false
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Scratch Buffer") { model.newScratchBuffer() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Tab") { model.newScratchBuffer() }
                .keyboardShortcut("t", modifiers: .command)
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
            Button("Toggle Sidebar") { sidebarVisible.toggle() }
                .keyboardShortcut("\\", modifiers: .command)
            Divider()
            Button("Quick Open…") { showQuickSwitcher = true }
                .keyboardShortcut("p", modifiers: .command)
            Divider()
            Button("Reveal in Finder") {
                if let id = model.bufferStore.activeBufferID,
                   let buf = model.bufferStore.buffer(id: id),
                   let url = buf.fileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        CommandGroup(replacing: .printItem) { }
    }
}
