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
    private var snapshotCapturedTokens: [UUID: UUID] = [:]
    private var metadataFollowUpDocumentIDs: Set<UUID> = []
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
            guard pendingRecoveries[documentID]?.token == token else { return }
            snapshotCapturedTokens[documentID] = token
            guard let currentDocument = documentProvider(documentID) else {
                snapshotCapturedTokens[documentID] = nil
                return
            }
            let record = currentDocument.recoverySnapshot()
            await acquireWriteGate(documentID: documentID)
            defer { releaseWriteGate(documentID: documentID) }
            guard !Task.isCancelled else {
                clearSnapshotState(documentID: documentID, token: token)
                return
            }
            do {
                try await writeRecovery(record)
            } catch {
                clearSnapshotState(documentID: documentID, token: token)
                return
            }
            completeRecovery(documentID: documentID, token: token)
        }
        pendingRecoveries[documentID] = PendingRecovery(token: token, task: task)
    }

    func ensureRecoveryScheduled(for document: DocumentSession) {
        if let pendingRecovery = pendingRecoveries[document.id] {
            if snapshotCapturedTokens[document.id] == pendingRecovery.token {
                metadataFollowUpDocumentIDs.insert(document.id)
            }
            return
        }
        scheduleRecovery(for: document)
    }

    func flushRecovery(for document: DocumentSession) async throws {
        try await flushRecovery(document.recoverySnapshot())
    }

    func flushRecovery(_ record: RecoveryRecord) async throws {
        let documentID = record.documentID
        cancelRecovery(documentID: documentID)
        await acquireWriteGate(documentID: documentID)
        defer { releaseWriteGate(documentID: documentID) }
        try Task.checkCancellation()
        try await writeRecovery(record)
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
        snapshotCapturedTokens[documentID] = nil
        metadataFollowUpDocumentIDs.remove(documentID)
    }

    private func clearSnapshotState(documentID: UUID, token: UUID) {
        guard snapshotCapturedTokens[documentID] == token else { return }
        snapshotCapturedTokens[documentID] = nil
        metadataFollowUpDocumentIDs.remove(documentID)
    }

    private func completeRecovery(documentID: UUID, token: UUID) {
        guard pendingRecoveries[documentID]?.token == token else {
            clearSnapshotState(documentID: documentID, token: token)
            return
        }
        pendingRecoveries[documentID] = nil
        snapshotCapturedTokens[documentID] = nil
        let requiresFollowUp = metadataFollowUpDocumentIDs.remove(documentID) != nil
        guard requiresFollowUp,
              let currentDocument = documentProvider(documentID),
              currentDocument.hasUnsavedChanges else { return }
        scheduleRecovery(for: currentDocument)
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

    private func writeRecovery(_ record: RecoveryRecord) async throws {
        let signpostID = PerformanceProbe.begin(PerformanceProbe.recoveryWrite)
        defer {
            PerformanceProbe.end(
                PerformanceProbe.recoveryWrite,
                id: signpostID
            )
        }
        try await repository.writeRecovery(record)
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

        if let matchingRecovery,
           recoveryIsAuthoritative(session: session, recovery: matchingRecovery) {
            return .recovery(matchingRecovery)
        }

        if !session.hasUnsavedChanges,
           session.fileReferenceID != nil,
           let fileReference {
            return .file(session, fileReference)
        }

        return .empty
    }

    static func recoveryIsAuthoritative(
        session: SessionRecord,
        recovery: RecoveryRecord
    ) -> Bool {
        guard recovery.documentID == session.documentID else { return false }
        // A session record has no text payload. When it says the document was
        // dirty, the matching recovery is the only durable user-text evidence,
        // even if an interrupted write left its generation one step behind.
        if session.hasUnsavedChanges { return true }

        if let sessionGeneration = session.documentGeneration,
           let recoveryGeneration = recovery.documentGeneration {
            return DocumentGeneration.isNewer(
                recoveryGeneration,
                than: sessionGeneration
            )
        }

        // Legacy v1 records have no generation. A matching base hash proves
        // that recovery was derived from the clean session's disk identity;
        // after a later successful save, the clean session hash changes and a
        // stale pre-save recovery no longer matches.
        if let sessionBaseHash = session.lastSavedHash,
           let recoveryBaseHash = recovery.baseDiskHash,
           recoveryBaseHash == sessionBaseHash {
            return true
        }
        return session.fileReferenceID == nil && !recovery.unsavedText.isEmpty
    }
}

extension SessionRecord: Equatable {
    static func == (lhs: SessionRecord, rhs: SessionRecord) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.documentID == rhs.documentID
            && lhs.documentGeneration == rhs.documentGeneration
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
            && lhs.documentGeneration == rhs.documentGeneration
            && lhs.fileReferenceID == rhs.fileReferenceID
            && lhs.filePathHint == rhs.filePathHint
            && lhs.unsavedText == rhs.unsavedText
            && lhs.baseDiskHash == rhs.baseDiskHash
            && lhs.baseDiskMTime == rhs.baseDiskMTime
            && lhs.lineEnding == rhs.lineEnding
            && lhs.selection == rhs.selection
            && lhs.scrollOffsetY == rhs.scrollOffsetY
            && lhs.savedAt == rhs.savedAt
            && lhs.pendingSaveAs == rhs.pendingSaveAs
    }
}
