import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let bufferStore = BufferStore()
    func newScratchBuffer() { bufferStore.createScratchBuffer() }
}
