import Foundation

struct RecoveryBuffer: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let bufferID: UUID
    let filePath: String?
    let unsavedText: String
    let savedAt: Date
}

struct BufferRecord: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let bufferID: UUID
    let filePath: String?
    let displayName: String
    let saveStateRaw: String
    let cursorLocation: Int
    let scrollOffsetY: Double
}

struct SessionSnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var buffers: [BufferRecord]
    var activeBufferID: UUID?
    var savedAt: Date
}
