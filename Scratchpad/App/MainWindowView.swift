import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let id = model.bufferStore.activeBufferID,
               let buffer = model.bufferStore.buffer(id: id) {
                EditorTextView(buffer: buffer)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            if model.bufferStore.buffers.isEmpty {
                model.bufferStore.createScratchBuffer()
            }
        }
    }
}
