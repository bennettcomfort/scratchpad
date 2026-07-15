import Foundation

struct DocumentSnapshot: Sendable {
    let documentID: UUID
    let generation: Int
    let text: String
    let fileReference: ExternalFileReference?
    let saveState: DocumentSaveState
    let hasUnsavedChanges: Bool
    let selection: TextSelection
    let scrollOffsetY: Double
    let lineEnding: LineEnding
    let lastSavedHash: String?
    let lastKnownDiskMTime: Date?
}
