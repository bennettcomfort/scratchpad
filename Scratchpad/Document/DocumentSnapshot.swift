import Foundation

enum DocumentGeneration {
    private static let modulus = UInt64(Int.max) + 1
    private static let halfRange = modulus / 2

    static func normalized(_ value: Int) -> Int {
        max(0, value)
    }

    static func next(after value: Int) -> Int {
        value == Int.max ? 0 : value + 1
    }

    static func previous(before value: Int) -> Int {
        value == 0 ? Int.max : value - 1
    }

    static func isNewer(_ candidate: Int, than baseline: Int) -> Bool {
        guard candidate >= 0, baseline >= 0 else { return false }
        let candidateValue = UInt64(candidate)
        let baselineValue = UInt64(baseline)
        let distance = candidateValue >= baselineValue
            ? candidateValue - baselineValue
            : modulus - baselineValue + candidateValue
        return distance > 0 && distance < halfRange
    }
}

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

extension DocumentSnapshot {
    var persistedBytes: Data {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let encodedText = lineEnding == .crlf
            ? normalized.replacingOccurrences(of: "\n", with: "\r\n")
            : normalized
        return Data(encodedText.utf8)
    }

    func recoveryRecord(
        pendingSaveAs: PendingSaveAsRecord? = nil,
        savedAt: Date = Date()
    ) -> RecoveryRecord {
        return RecoveryRecord(
            schemaVersion: 1,
            documentID: documentID,
            documentGeneration: generation,
            fileReferenceID: fileReference?.bookmarkID,
            filePathHint: fileReference?.pathHint,
            unsavedText: text,
            baseDiskHash: lastSavedHash,
            baseDiskMTime: lastKnownDiskMTime,
            lineEnding: lineEnding,
            selection: selection,
            scrollOffsetY: scrollOffsetY,
            savedAt: savedAt,
            pendingSaveAs: pendingSaveAs
        )
    }


    func recoveryRecord(
        verifiedSaveAs result: FileSaveResult,
        savedAt: Date = Date()
    ) -> RecoveryRecord {
        RecoveryRecord(
            schemaVersion: 1,
            documentID: documentID,
            documentGeneration: generation,
            fileReferenceID: result.reference.bookmarkID,
            filePathHint: result.reference.pathHint,
            unsavedText: text,
            baseDiskHash: result.contentHash,
            baseDiskMTime: result.modificationDate,
            lineEnding: result.lineEnding,
            selection: selection,
            scrollOffsetY: scrollOffsetY,
            savedAt: savedAt,
            pendingSaveAs: nil
        )
    }
}
