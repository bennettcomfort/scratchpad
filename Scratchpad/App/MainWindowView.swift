import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()

            if let id = model.bufferStore.activeBufferID,
               let buffer = model.bufferStore.buffer(id: id) {
                EditorTextView(
                    buffer: buffer,
                    onEdit: { model.sessionService.noteBufferEdited($0) })
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
