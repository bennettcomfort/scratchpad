import Foundation

struct SessionRecord: Codable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let fileReferenceID: UUID?
    let displayName: String
    let saveState: DocumentSaveState
    let hasUnsavedChanges: Bool
    let selection: TextSelection
    let scrollOffsetY: Double
    let lineEnding: LineEnding
    let lastSavedHash: String?
    let lastKnownDiskMTime: Date?
    let windowFrame: CGRect
    let didCloseCleanly: Bool
    let savedAt: Date
}

struct RecoveryRecord: Codable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let fileReferenceID: UUID?
    let filePathHint: String?
    let unsavedText: String
    let baseDiskHash: String?
    let baseDiskMTime: Date?
    let lineEnding: LineEnding
    let selection: TextSelection
    let scrollOffsetY: Double
    let savedAt: Date
}

struct BookmarkRecord: Codable, Sendable {
    let id: UUID
    let bookmarkData: Data
    let pathHint: String
    let updatedAt: Date
}

struct BookmarkCollection: Codable, Sendable {
    let schemaVersion: Int
    let records: [BookmarkRecord]
}
