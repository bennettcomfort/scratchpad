import Foundation

struct FileOpenResult: Equatable, Sendable {
    let reference: ExternalFileReference
    let text: String
    let displayName: String
    let lineEnding: LineEnding
    let contentHash: String
    let modificationDate: Date
}

struct FileSaveResult: Equatable, Sendable {
    let documentID: UUID
    let initiatingGeneration: Int
    let reference: ExternalFileReference
    let displayName: String
    let lineEnding: LineEnding
    let contentHash: String
    let modificationDate: Date
}

enum ExternalFileStatus: Equatable, Sendable {
    case unchanged
    case changed(contentHash: String, modificationDate: Date)
    case missing
    case readOnly
    case accessRequiresReselection
}

enum FileServiceError: Error, Equatable, Sendable {
    case missing
    case readOnly
    case accessRequiresReselection
    case accessFailed
    case invalidUTF8
    case missingFileReference
    case missingBaseMetadata
    case conflict(contentHash: String, modificationDate: Date)
    case verificationFailed
    case readFailed
    case writeFailed
}

protocol FileServicing: Sendable {
    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult
    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult
    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult
    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus
}
