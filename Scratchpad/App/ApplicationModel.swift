import Foundation
import Observation

enum LaunchState: Equatable {
    case restoring
    case ready
    case failed(message: String)
}

enum ApplicationModelLaunchError: Error, Equatable {
    case missingServices
    case unresolvedBookmark(UUID)
}

@MainActor
@Observable
final class ApplicationModel {
    private(set) var document: DocumentSession
    private(set) var launchState: LaunchState
    private(set) var launchAttempt = 0

    @ObservationIgnored
    private let servicesFactory: (@MainActor @Sendable () throws -> ApplicationServices)?
    @ObservationIgnored
    private var services: ApplicationServices?
    @ObservationIgnored
    private var recoveryCoordinator: RecoveryCoordinator?
    @ObservationIgnored
    private var startedLaunchAttempt: Int?

    init(
        document: DocumentSession = DocumentSession(),
        launchState: LaunchState = .ready,
        servicesFactory: (@MainActor @Sendable () throws -> ApplicationServices)? = nil
    ) {
        self.document = document
        self.launchState = launchState
        self.servicesFactory = servicesFactory
    }

    static func live() -> ApplicationModel {
        ApplicationModel(
            launchState: .restoring,
            servicesFactory: { try ApplicationServices.live() }
        )
    }

    func requestLaunchRetry() {
        guard case .failed = launchState else { return }
        launchAttempt += 1
        launchState = .restoring
    }

    func handleCurrentDocumentEdit(_ editedDocument: DocumentSession) {
        guard launchState == .ready,
              editedDocument === document,
              editedDocument.id == document.id,
              let recoveryCoordinator else { return }
        recoveryCoordinator.scheduleRecovery(for: editedDocument)
    }

    func restoreCurrentLaunchAttempt(windowFrame: CGRect) async {
        let attempt = launchAttempt
        guard launchState == .restoring,
              startedLaunchAttempt != attempt,
              !Task.isCancelled else { return }
        startedLaunchAttempt = attempt

        do {
            let services = try resolvedServices()
            let coordinator = resolvedRecoveryCoordinator(services: services)
            _ = try await restoreAtLaunch(
                repository: services.repository,
                bookmarks: services.bookmarks,
                files: services.files,
                recoveryCoordinator: coordinator,
                windowFrame: windowFrame
            )
            try Task.checkCancellation()
            guard launchAttempt == attempt else { return }
            launchState = .ready
        } catch is CancellationError {
            return
        } catch {
            guard launchAttempt == attempt else { return }
            launchState = .failed(
                message: "Scratchpad couldn't restore this session safely."
            )
        }
    }

    private func resolvedServices() throws -> ApplicationServices {
        if let services { return services }
        guard let servicesFactory else {
            throw ApplicationModelLaunchError.missingServices
        }
        let created = try servicesFactory()
        services = created
        return created
    }

    private func resolvedRecoveryCoordinator(
        services: ApplicationServices
    ) -> RecoveryCoordinator {
        if let recoveryCoordinator { return recoveryCoordinator }
        let created = RecoveryCoordinator(
            repository: services.repository,
            clock: services.recoveryClock,
            documentProvider: { [weak self] documentID in
                guard let self, self.document.id == documentID else { return nil }
                return self.document
            }
        )
        recoveryCoordinator = created
        return created
    }

    func restoreAtLaunch(
        repository: any SessionPersisting,
        bookmarks: any BookmarkAccessing,
        files: any FileServicing,
        recoveryCoordinator: RecoveryCoordinator,
        windowFrame: CGRect
    ) async throws -> RestoreSource {
        let session = try await repository.loadSession()
        let recovery: RecoveryRecord?
        let cleanFileReference: ExternalFileReference?

        if let session {
            recovery = try await repository.loadRecovery(documentID: session.documentID)
            if !session.hasUnsavedChanges,
               let bookmarkID = session.fileReferenceID {
                cleanFileReference = try await requireReference(
                    bookmarkID: bookmarkID,
                    bookmarks: bookmarks
                )
            } else {
                cleanFileReference = nil
            }
        } else {
            recovery = nil
            cleanFileReference = nil
        }

        let source = RecoveryCoordinator.restoreSource(
            session: session,
            recovery: recovery,
            fileReference: cleanFileReference
        )
        let restoredFileReference: ExternalFileReference?
        if case .recovery(let recovery) = source,
           let bookmarkID = recovery.fileReferenceID {
            restoredFileReference = try await requireReference(
                bookmarkID: bookmarkID,
                bookmarks: bookmarks
            )
        } else {
            restoredFileReference = cleanFileReference
        }
        try await applyLaunchSource(
            source,
            session: session,
            fileReference: restoredFileReference,
            files: files
        )
        try await recoveryCoordinator.flushSession(
            for: document,
            windowFrame: windowFrame,
            didCloseCleanly: false
        )
        return source
    }

    private func requireReference(
        bookmarkID: UUID,
        bookmarks: any BookmarkAccessing
    ) async throws -> ExternalFileReference {
        guard let reference = try await bookmarks.reference(for: bookmarkID) else {
            throw ApplicationModelLaunchError.unresolvedBookmark(bookmarkID)
        }
        return reference
    }

    private func applyLaunchSource(
        _ source: RestoreSource,
        session: SessionRecord?,
        fileReference: ExternalFileReference?,
        files: any FileServicing
    ) async throws {
        switch source {
        case .recovery(let recovery):
            let containsPreservationRequiredText = !recovery.unsavedText.isEmpty
            let restoredSaveState: DocumentSaveState
            if fileReference == nil,
               containsPreservationRequiredText {
                restoredSaveState = .edited
            } else {
                restoredSaveState = session?.saveState ?? .edited
            }
            let restoredDocument = DocumentSession(
                id: recovery.documentID,
                fileReference: fileReference,
                displayName: session?.displayName ?? "Untitled",
                saveState: restoredSaveState,
                hasUnsavedChanges: session?.hasUnsavedChanges == true
                    || containsPreservationRequiredText,
                lastSavedHash: recovery.baseDiskHash,
                lastKnownDiskMTime: recovery.baseDiskMTime,
                lineEnding: recovery.lineEnding,
                selection: recovery.selection,
                scrollOffsetY: recovery.scrollOffsetY
            )
            restoredDocument.replaceEntireContents(
                recovery.unsavedText,
                source: .sessionRestore,
                selection: recovery.selection
            )
            document = restoredDocument
        case .file(let session, let reference):
            let openedFile = try await files.open(reference)
            let restoredDocument = DocumentSession(
                id: session.documentID,
                fileReference: reference,
                displayName: openedFile.displayName,
                saveState: .clean,
                hasUnsavedChanges: false,
                lastSavedHash: openedFile.contentHash,
                lastKnownDiskMTime: openedFile.modificationDate,
                lineEnding: openedFile.lineEnding,
                selection: session.selection,
                scrollOffsetY: session.scrollOffsetY
            )
            restoredDocument.replaceEntireContents(
                openedFile.text,
                source: .fileOpen,
                selection: session.selection
            )
            document = restoredDocument
        case .empty:
            document = DocumentSession()
        }
    }
}
