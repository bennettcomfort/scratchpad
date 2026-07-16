import Foundation

struct PendingSaveAsRecord: Codable, Sendable, Equatable {
    let destinationFileReferenceID: UUID
    let destinationPathHint: String?
    let expectedContentHash: String
}

struct SessionRecord: Codable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let documentGeneration: Int?
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

    init(
        schemaVersion: Int,
        documentID: UUID,
        documentGeneration: Int? = nil,
        fileReferenceID: UUID?,
        displayName: String,
        saveState: DocumentSaveState,
        hasUnsavedChanges: Bool,
        selection: TextSelection,
        scrollOffsetY: Double,
        lineEnding: LineEnding,
        lastSavedHash: String?,
        lastKnownDiskMTime: Date?,
        windowFrame: CGRect,
        didCloseCleanly: Bool,
        savedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.documentID = documentID
        self.documentGeneration = documentGeneration
        self.fileReferenceID = fileReferenceID
        self.displayName = displayName
        self.saveState = saveState
        self.hasUnsavedChanges = hasUnsavedChanges
        self.selection = selection
        self.scrollOffsetY = scrollOffsetY
        self.lineEnding = lineEnding
        self.lastSavedHash = lastSavedHash
        self.lastKnownDiskMTime = lastKnownDiskMTime
        self.windowFrame = windowFrame
        self.didCloseCleanly = didCloseCleanly
        self.savedAt = savedAt
    }
}

struct RecoveryRecord: Codable, Sendable {
    let schemaVersion: Int
    let documentID: UUID
    let documentGeneration: Int?
    let fileReferenceID: UUID?
    let filePathHint: String?
    let unsavedText: String
    let baseDiskHash: String?
    let baseDiskMTime: Date?
    let lineEnding: LineEnding
    let selection: TextSelection
    let scrollOffsetY: Double
    let savedAt: Date
    let pendingSaveAs: PendingSaveAsRecord?

    init(
        schemaVersion: Int,
        documentID: UUID,
        documentGeneration: Int? = nil,
        fileReferenceID: UUID?,
        filePathHint: String?,
        unsavedText: String,
        baseDiskHash: String?,
        baseDiskMTime: Date?,
        lineEnding: LineEnding,
        selection: TextSelection,
        scrollOffsetY: Double,
        savedAt: Date,
        pendingSaveAs: PendingSaveAsRecord? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.documentID = documentID
        self.documentGeneration = documentGeneration
        self.fileReferenceID = fileReferenceID
        self.filePathHint = filePathHint
        self.unsavedText = unsavedText
        self.baseDiskHash = baseDiskHash
        self.baseDiskMTime = baseDiskMTime
        self.lineEnding = lineEnding
        self.selection = selection
        self.scrollOffsetY = scrollOffsetY
        self.savedAt = savedAt
        self.pendingSaveAs = pendingSaveAs
    }
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
