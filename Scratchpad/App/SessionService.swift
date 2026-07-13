import Foundation

@MainActor
final class SessionService {
    private let bufferStore: BufferStore
    private let writer: SessionWriter
    private let recoveryDebouncer = Debouncer(delay: .seconds(2))

    init(bufferStore: BufferStore, writer: SessionWriter) {
        self.bufferStore = bufferStore
        self.writer = writer
    }

    private func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            buffers: bufferStore.buffers.map {
                BufferRecord(bufferID: $0.id, filePath: $0.fileURL?.path,
                             displayName: $0.displayName, saveStateRaw: $0.saveState.rawValue,
                             cursorLocation: $0.cursorLocation, scrollOffsetY: $0.scrollOffsetY)
            },
            activeBufferID: bufferStore.activeBufferID,
            savedAt: Date())
    }

    /// Debounced 1–3 s after edits while dirty (SPEC §8).
    func noteBufferEdited(_ b: OpenBuffer) {
        let rb = RecoveryBuffer(bufferID: b.id, filePath: b.fileURL?.path,
                                unsavedText: b.text, savedAt: Date())
        recoveryDebouncer.schedule { [writer] in
            Task { await writer.writeRecovery(rb) }
        }
    }

    /// Buffer open/close/switch, window changes, terminate.
    func noteStructuralChange() {
        let s = snapshot()
        Task { await writer.writeSession(s) }
    }

    /// Silent restore — NO prompt, ever (SPEC §8).
    func restoreOnLaunch() async {
        let session = await writer.loadSession()
        let recoveries = Dictionary(uniqueKeysWithValues:
            await writer.loadRecoveries().map { ($0.bufferID, $0) })

        guard let session, !session.buffers.isEmpty else {
            if bufferStore.buffers.isEmpty { bufferStore.createScratchBuffer() }
            return
        }
        for record in session.buffers {
            let b = OpenBuffer(id: record.bufferID,
                               fileURL: record.filePath.map { URL(fileURLWithPath: $0) },
                               displayName: record.displayName)
            if let rec = recoveries[record.bufferID] {
                b.replaceEntireContents(rec.unsavedText)
                b.saveState = SaveState(rawValue: record.saveStateRaw) ?? .scratch
            }
            b.cursorLocation = record.cursorLocation
            b.scrollOffsetY = record.scrollOffsetY
            bufferStore.adopt(b)
        }
        bufferStore.activeBufferID = session.activeBufferID ?? bufferStore.buffers.last?.id
        if bufferStore.buffers.isEmpty { bufferStore.createScratchBuffer() }
    }
}
