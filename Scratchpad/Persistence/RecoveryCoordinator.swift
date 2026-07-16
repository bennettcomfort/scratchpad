import Foundation

protocol RecoveryClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousRecoveryClock: RecoveryClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

enum RestoreSource: Equatable, Sendable {
    case recovery(RecoveryRecord)
    case file(SessionRecord, ExternalFileReference)
    case empty
}

@MainActor
final class RecoveryCoordinator {
    private struct PendingRecovery {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let repository: any SessionPersisting
    private let clock: any RecoveryClock
    private let documentProvider: @MainActor @Sendable (UUID) -> DocumentSession?
    private var pendingRecoveries: [UUID: PendingRecovery] = [:]
    private var activeWriteDocumentIDs: Set<UUID> = []
    private var writeWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    init(
        repository: any SessionPersisting,
        clock: any RecoveryClock,
        documentProvider: @escaping @MainActor @Sendable (UUID) -> DocumentSession?
    ) {
        self.repository = repository
        self.clock = clock
        self.documentProvider = documentProvider
    }

    func scheduleRecovery(for document: DocumentSession) {
        let documentID = document.id
        cancelRecovery(documentID: documentID)
        let token = UUID()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard let currentDocument = documentProvider(documentID) else { return }
            let record = currentDocument.recoverySnapshot()
            await acquireWriteGate(documentID: documentID)
            defer { releaseWriteGate(documentID: documentID) }
            guard !Task.isCancelled else { return }
            do {
                try await repository.writeRecovery(record)
            } catch {
                return
            }
            if pendingRecoveries[documentID]?.token == token {
                pendingRecoveries[documentID] = nil
            }
        }
        pendingRecoveries[documentID] = PendingRecovery(token: token, task: task)
    }

    func flushRecovery(for document: DocumentSession) async throws {
        let documentID = document.id
        pendingRecoveries.removeValue(forKey: documentID)?.task.cancel()
        let record = document.recoverySnapshot()
        await acquireWriteGate(documentID: documentID)
        defer { releaseWriteGate(documentID: documentID) }
        try Task.checkCancellation()
        try await repository.writeRecovery(record)
    }

    func flushSession(
        for document: DocumentSession,
        windowFrame: CGRect,
        didCloseCleanly: Bool
    ) async throws {
        let record = document.sessionRecord(
            windowFrame: windowFrame,
            didCloseCleanly: didCloseCleanly
        )
        try await repository.writeSession(record)
    }

    func cancelRecovery(documentID: UUID) {
        pendingRecoveries.removeValue(forKey: documentID)?.task.cancel()
    }

    private func acquireWriteGate(documentID: UUID) async {
        guard activeWriteDocumentIDs.contains(documentID) else {
            activeWriteDocumentIDs.insert(documentID)
            return
        }
        await withCheckedContinuation { continuation in
            writeWaiters[documentID, default: []].append(continuation)
        }
    }

    private func releaseWriteGate(documentID: UUID) {
        guard var waiters = writeWaiters[documentID], !waiters.isEmpty else {
            activeWriteDocumentIDs.remove(documentID)
            writeWaiters[documentID] = nil
            return
        }
        let next = waiters.removeFirst()
        writeWaiters[documentID] = waiters.isEmpty ? nil : waiters
        next.resume()
    }

    static func restoreSource(
        session: SessionRecord?,
        recovery: RecoveryRecord?,
        fileReference: ExternalFileReference?
    ) -> RestoreSource {
        guard let session else { return .empty }
        let matchingRecovery = recovery.flatMap { record in
            record.documentID == session.documentID ? record : nil
        }

        if session.hasUnsavedChanges,
           let matchingRecovery {
            return .recovery(matchingRecovery)
        }

        if session.fileReferenceID == nil,
           let matchingRecovery,
           !matchingRecovery.unsavedText.isEmpty {
            return .recovery(matchingRecovery)
        }

        if !session.hasUnsavedChanges,
           session.fileReferenceID != nil,
           let fileReference {
            return .file(session, fileReference)
        }

        return .empty
    }
}

extension SessionRecord: Equatable {
    static func == (lhs: SessionRecord, rhs: SessionRecord) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.documentID == rhs.documentID
            && lhs.fileReferenceID == rhs.fileReferenceID
            && lhs.displayName == rhs.displayName
            && lhs.saveState == rhs.saveState
            && lhs.hasUnsavedChanges == rhs.hasUnsavedChanges
            && lhs.selection == rhs.selection
            && lhs.scrollOffsetY == rhs.scrollOffsetY
            && lhs.lineEnding == rhs.lineEnding
            && lhs.lastSavedHash == rhs.lastSavedHash
            && lhs.lastKnownDiskMTime == rhs.lastKnownDiskMTime
            && lhs.windowFrame == rhs.windowFrame
            && lhs.didCloseCleanly == rhs.didCloseCleanly
            && lhs.savedAt == rhs.savedAt
    }
}

extension RecoveryRecord: Equatable {
    static func == (lhs: RecoveryRecord, rhs: RecoveryRecord) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.documentID == rhs.documentID
            && lhs.fileReferenceID == rhs.fileReferenceID
            && lhs.filePathHint == rhs.filePathHint
            && lhs.unsavedText == rhs.unsavedText
            && lhs.baseDiskHash == rhs.baseDiskHash
            && lhs.baseDiskMTime == rhs.baseDiskMTime
            && lhs.lineEnding == rhs.lineEnding
            && lhs.selection == rhs.selection
            && lhs.scrollOffsetY == rhs.scrollOffsetY
            && lhs.savedAt == rhs.savedAt
    }
}
