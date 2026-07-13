import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var themeManager = ThemeManager()

    var body: some View {
        VStack(spacing: 0) {
            if let id = model.bufferStore.activeBufferID,
               let buffer = model.bufferStore.buffer(id: id) {
                EditorTextView(
                    buffer: buffer,
                    onEdit: { model.sessionService.noteBufferEdited($0) },
                    theme: themeManager.current)
                StatusBarView(buffer: buffer, theme: themeManager.current)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            Task {
                await model.sessionService.restoreOnLaunch()
                model.startGlobalHotkey()
            }
        }
    }
}
