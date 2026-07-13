import Foundation
import Observation

@MainActor @Observable
final class BufferStore {
    private(set) var buffers: [OpenBuffer] = []
    var activeBufferID: UUID?

    @discardableResult
    func createScratchBuffer() -> OpenBuffer {
        let b = OpenBuffer()
        buffers.append(b)
        activeBufferID = b.id
        return b
    }

    func buffer(id: UUID) -> OpenBuffer? { buffers.first { $0.id == id } }

    func close(id: UUID) {
        buffers.removeAll { $0.id == id }
        if activeBufferID == id { activeBufferID = buffers.last?.id }
    }
}
