import AppKit
import Foundation
import Observation
import OSLog

enum LaunchState: Equatable {
    case restoring
    case ready
    case failed(message: String)
}

enum ApplicationModelLaunchError: Error, Equatable {
    case missingServices
}

enum DocumentOperationState: Equatable, Sendable {
    case idle
    case opening(ExternalFileReference)
    case saving(UUID)
    case closing
    case terminating
}

@MainActor
@Observable
final class ApplicationModel {
    private(set) var document: DocumentSession
    private(set) var metrics: DocumentMetrics
    private(set) var launchState: LaunchState
    private(set) var launchAttempt = 0
    private(set) var operationState: DocumentOperationState = .idle
    private(set) var restoredWindowFrame: CGRect?
    let settings: SettingsStore
    var banner: ErrorBanner?

    var pendingDecision: DocumentDecision? { decisionCoordinator.pending }
    var allowsDocumentEditing: Bool {
        switch operationState {
        case .idle, .saving:
            true
        case .opening, .closing, .terminating:
            false
        }
    }

    @ObservationIgnored
    private let servicesFactory: (@MainActor @Sendable () throws -> ApplicationServices)?
    @ObservationIgnored
    private var services: ApplicationServices?
    @ObservationIgnored
    private var recoveryCoordinator: RecoveryCoordinator?
    @ObservationIgnored
    private var externalChangeMonitor: ExternalChangeMonitor?
    @ObservationIgnored
    private var recoveryCleanupRequiredDocumentID: UUID?
    @ObservationIgnored
    private var idleOperationWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    @ObservationIgnored
    private var startedLaunchAttempt: Int?
    @ObservationIgnored
    private let panelProvider: (any FilePanelProviding)?
    @ObservationIgnored
    private let decisionCoordinator: DocumentDecisionCoordinator
    @ObservationIgnored
    private let windowFrameProvider: @MainActor () -> CGRect
    @ObservationIgnored
    private let requestEditorFocus: @MainActor () -> Void
    @ObservationIgnored
    private let metricsCoordinator: MetricsCoordinator

    init(
        document: DocumentSession = DocumentSession(),
        settings: SettingsStore = SettingsStore.transient(),
        launchState: LaunchState = .ready,
        servicesFactory: (@MainActor @Sendable () throws -> ApplicationServices)? = nil,
        panelProvider: (any FilePanelProviding)? = nil,
        decisionCoordinator: DocumentDecisionCoordinator = DocumentDecisionCoordinator(),
        windowFrameProvider: @escaping @MainActor () -> CGRect = { .zero },
        requestEditorFocus: @escaping @MainActor () -> Void = {},
        metricsCoordinator: MetricsCoordinator = MetricsCoordinator()
    ) {
        self.document = document
        self.metrics = .empty
        self.settings = settings
        self.launchState = launchState
        self.servicesFactory = servicesFactory
        self.panelProvider = panelProvider
        self.decisionCoordinator = decisionCoordinator
        self.windowFrameProvider = windowFrameProvider
        self.requestEditorFocus = requestEditorFocus
        self.metricsCoordinator = metricsCoordinator
        scheduleMetrics(for: document)
        observeMetricsSettings()
    }

    static func live(
        settings: SettingsStore? = nil,
        applicationSupportPaths: ApplicationSupportPaths? = nil
    ) -> ApplicationModel {
        let resolvedSettings = settings ?? SettingsStore(
            defaults: .standard,
            launchService: LaunchAtLoginService()
        )
        return ApplicationModel(
            settings: resolvedSettings,
            launchState: .restoring,
            servicesFactory: {
                try ApplicationServices.live(paths: applicationSupportPaths)
            },
            panelProvider: FilePanelProvider(),
            windowFrameProvider: {
                NSApp.keyWindow?.frame
                    ?? CGRect(x: 0, y: 0, width: 820, height: 640)
            },
            requestEditorFocus: {
                guard let contentView = NSApp.keyWindow?.contentView,
                      let editor = contentView.firstDescendant(of: ScratchTextView.self) else {
                    return
                }
                NSApp.keyWindow?.makeFirstResponder(editor)
            }
        )
    }

    // MARK: - Document Operations

    func resolvePendingDecision(with resolution: DocumentDecisionResolution) {
        decisionCoordinator.resolvePending(with: resolution)
    }

    func startExternalChangeMonitoring() {
        do {
            let services = try resolvedServices()
            let monitor = resolvedExternalChangeMonitor(services: services)
            monitor.start(document: document) { [weak self] documentID, generation, status in
                guard let self else { return }
                await self.receiveExternalFileStatus(
                    documentID: documentID,
                    generation: generation,
                    status: status,
                    services: services
                )
            }
        } catch {
            publishPersistenceBanner(error)
        }
    }

    func requestNewDocument() async {
        guard launchState == .ready,
              operationState == .idle else { return }
        operationState = .closing
        defer { finishOperation() }

        guard let dependencies = operationDependencies(),
              await flushRecovery(using: dependencies.recovery) else { return }
        guard await approveReplacement(
            .newUntitled,
            dependencies: dependencies
        ) else { return }
        await persistAndReplaceCurrentDocument(
            with: DocumentSession(),
            using: dependencies
        )
    }

    func requestOpen() async {
        guard launchState == .ready,
              let panelProvider,
              let selectedURL = await panelProvider.selectFileToOpen() else { return }

        let services: ApplicationServices
        do {
            services = try resolvedServices()
        } catch {
            publishPersistenceBanner(error)
            return
        }

        let reference: ExternalFileReference
        do {
            reference = try await services.bookmarks.storeSelection(selectedURL)
        } catch {
            publishBookmarkBanner(error, path: selectedURL.path)
            return
        }

        if case .opening(reference) = operationState { return }
        guard operationState == .idle else { return }
        operationState = .opening(reference)
        defer { finishOperation() }

        let recovery = resolvedRecoveryCoordinator(services: services)
        guard await flushRecovery(using: recovery) else { return }
        let dependencies = OperationDependencies(services: services, recovery: recovery)

        let openedFile: FileOpenResult
        do {
            openedFile = try await services.files.open(reference)
        } catch {
            publishFileBanner(error, path: reference.pathHint)
            return
        }

        guard await approveReplacement(
            .open(reference),
            dependencies: dependencies
        ) else { return }
        await applyOpenedFile(openedFile, using: dependencies)
    }

    func save() async -> Bool {
        guard launchState == .ready,
              operationState == .idle else { return false }
        operationState = .saving(document.id)
        defer { finishOperation() }
        guard let dependencies = operationDependencies() else { return false }
        return await performSave(document.snapshot(), using: dependencies)
    }

    func saveAs() async -> Bool {
        guard launchState == .ready,
              operationState == .idle else { return false }
        operationState = .saving(document.id)
        defer { finishOperation() }
        guard let dependencies = operationDependencies() else { return false }
        return await performSaveAs(document.snapshot(), using: dependencies)
    }

    func requestClose() async -> Bool {
        // A failed launch has no editable text in memory; recovery and session
        // records on disk are untouched, so closing cannot lose anything.
        if case .failed = launchState { return true }
        guard launchState == .ready else { return false }
        return await requestExit(.closeWindow, operation: .closing)
    }

    func requestTermination() async -> Bool {
        if case .failed = launchState { return true }
        guard launchState == .ready else { return false }
        return await requestExit(.terminateApplication, operation: .terminating)
    }

    func flushLifecycleState(didCloseCleanly: Bool) async -> Bool {
        guard launchState == .ready,
              let dependencies = operationDependencies() else { return false }
        let boundary = currentDocumentBoundary()
        guard await flushRecovery(using: dependencies.recovery) else { return false }
        do {
            try await dependencies.recovery.flushSession(
                for: document,
                windowFrame: windowFrameProvider(),
                didCloseCleanly: didCloseCleanly
            )
        } catch {
            publishPersistenceBanner(error)
            return false
        }
        return await revalidate(boundary, using: dependencies)
    }

    func presentPendingLifecycleFailure() {
        banner = ErrorBanner(
            id: UUID(),
            message: "Scratchpad couldn't preserve the latest session state.",
            actions: [.retry(.preserveCurrentDocument), .dismiss]
        )
    }

    func retryBannerOperation(_ operation: BannerRetryOperation) async {
        banner = nil
        switch operation {
        case .preserveCurrentDocument:
            _ = await flushLifecycleState(didCloseCleanly: false)
        case .saveCurrentDocument:
            _ = await save()
        }
    }

    // MARK: - Launch Restoration

    func requestLaunchRetry() {
        guard case .failed = launchState else { return }
        launchAttempt += 1
        launchState = .restoring
    }

    func handleCurrentDocumentEdit(_ editedDocument: DocumentSession) {
        guard launchState == .ready,
              editedDocument === document,
              editedDocument.id == document.id else { return }
        scheduleMetrics(for: editedDocument)
        guard let recoveryCoordinator else { return }
        if recoveryCleanupRequiredDocumentID == editedDocument.id {
            recoveryCleanupRequiredDocumentID = nil
        }
        recoveryCoordinator.scheduleRecovery(for: editedDocument)
    }

    func handleCurrentDocumentStateChange(_ changedDocument: DocumentSession) {
        guard launchState == .ready,
              changedDocument === document,
              changedDocument.id == document.id,
              changedDocument.hasUnsavedChanges,
              let recoveryCoordinator else { return }
        recoveryCoordinator.ensureRecoveryScheduled(for: changedDocument)
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
            startExternalChangeMonitoring()
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

    private func resolvedExternalChangeMonitor(
        services: ApplicationServices
    ) -> ExternalChangeMonitor {
        if let externalChangeMonitor { return externalChangeMonitor }
        let created = ExternalChangeMonitor(
            fileService: services.files,
            clock: services.recoveryClock
        )
        externalChangeMonitor = created
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
        restoredWindowFrame = session?.windowFrame
        var recovery: RecoveryRecord?
        let cleanFileReference: ExternalFileReference?

        if let session {
            recovery = try await repository.loadRecovery(documentID: session.documentID)
            if let loadedRecovery = recovery,
               loadedRecovery.documentID == session.documentID,
               loadedRecovery.pendingSaveAs != nil,
               pendingSaveAsCanReconcile(
                   session: session,
                   recovery: loadedRecovery
               ) {
                recovery = await reconcilePendingSaveAs(
                    loadedRecovery,
                    sessionGeneration: session.documentGeneration,
                    bookmarks: bookmarks,
                    files: files,
                    recoveryCoordinator: recoveryCoordinator
                )
            }
            let recoveryWins = recovery.map {
                RecoveryCoordinator.recoveryIsAuthoritative(
                    session: session,
                    recovery: $0
                )
            } == true
            if !recoveryWins,
               !session.hasUnsavedChanges,
               let bookmarkID = session.fileReferenceID {
                cleanFileReference = await availableReference(
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

        var source = RecoveryCoordinator.restoreSource(
            session: session,
            recovery: recovery,
            fileReference: cleanFileReference
        )
        let restoredFileReference: ExternalFileReference?
        var detachesRecoveryFromFile = false
        if case .recovery(let recovery) = source,
           let bookmarkID = recovery.fileReferenceID {
            restoredFileReference = await availableReference(
                bookmarkID: bookmarkID,
                bookmarks: bookmarks
            )
            detachesRecoveryFromFile = restoredFileReference == nil
        } else {
            restoredFileReference = cleanFileReference
        }
        if case .empty = source,
           let session,
           !session.hasUnsavedChanges,
           session.fileReferenceID != nil {
            // A clean file-backed session whose file can't be resolved holds no
            // unsaved text, so it falls back to an empty untitled document.
            replaceCurrentDocument(with: DocumentSession())
            publishUnavailableFileBanner(displayName: session.displayName)
        } else {
            source = await applyLaunchSource(
                source,
                session: session,
                fileReference: restoredFileReference,
                detachesRecoveryFromFile: detachesRecoveryFromFile,
                files: files
            )
        }
        try await recoveryCoordinator.flushSession(
            for: document,
            windowFrame: session?.windowFrame ?? windowFrame,
            didCloseCleanly: false
        )
        return source
    }

    private func reconcilePendingSaveAs(
        _ recovery: RecoveryRecord,
        sessionGeneration: Int?,
        bookmarks: any BookmarkAccessing,
        files: any FileServicing,
        recoveryCoordinator: RecoveryCoordinator
    ) async -> RecoveryRecord {
        guard let pending = recovery.pendingSaveAs else { return recovery }
        let destinationReference: ExternalFileReference
        do {
            guard let resolved = try await bookmarks.reference(
                for: pending.destinationFileReferenceID
            ) else { return recovery }
            destinationReference = resolved
        } catch {
            return recovery
        }

        let opened: FileOpenResult
        do {
            opened = try await files.open(destinationReference)
        } catch {
            return recovery
        }
        guard opened.contentHash == pending.expectedContentHash else {
            return recovery
        }
        guard let verifiedGeneration = nextPersistedGeneration(
            recovery.documentGeneration,
            sessionGeneration
        ) else { return recovery }

        let verified = RecoveryRecord(
            schemaVersion: recovery.schemaVersion,
            documentID: recovery.documentID,
            documentGeneration: verifiedGeneration,
            fileReferenceID: destinationReference.bookmarkID,
            filePathHint: destinationReference.pathHint,
            unsavedText: recovery.unsavedText,
            baseDiskHash: opened.contentHash,
            baseDiskMTime: opened.modificationDate,
            lineEnding: opened.lineEnding,
            selection: recovery.selection,
            scrollOffsetY: recovery.scrollOffsetY,
            savedAt: Date(),
            pendingSaveAs: nil
        )
        do {
            try await recoveryCoordinator.flushRecovery(verified)
            return verified
        } catch {
            return recovery
        }
    }

    private func pendingSaveAsCanReconcile(
        session: SessionRecord,
        recovery: RecoveryRecord
    ) -> Bool {
        if session.hasUnsavedChanges { return true }
        if let sessionGeneration = session.documentGeneration,
           let recoveryGeneration = recovery.documentGeneration {
            return recoveryGeneration == sessionGeneration
                || DocumentGeneration.isNewer(
                    recoveryGeneration,
                    than: sessionGeneration
                )
        }
        return RecoveryCoordinator.recoveryIsAuthoritative(
            session: session,
            recovery: recovery
        )
    }

    private func availableReference(
        bookmarkID: UUID,
        bookmarks: any BookmarkAccessing
    ) async -> ExternalFileReference? {
        do {
            return try await bookmarks.reference(for: bookmarkID)
        } catch {
            AppLog.bookmarks.error(
                "Launch bookmark lookup failed: \(String(describing: type(of: error)), privacy: .public)"
            )
            return nil
        }
    }

    private func applyLaunchSource(
        _ source: RestoreSource,
        session: SessionRecord?,
        fileReference: ExternalFileReference?,
        detachesRecoveryFromFile: Bool,
        files: any FileServicing
    ) async -> RestoreSource {
        switch source {
        case .recovery(let recovery):
            let restoredSaveState: DocumentSaveState
            if detachesRecoveryFromFile {
                restoredSaveState = .edited
            } else {
                switch session?.saveState {
                case .clean, .untitled, .none:
                    restoredSaveState = .edited
                case .edited, .conflicted, .deleted, .readOnly:
                    restoredSaveState = session?.saveState ?? .edited
                }
            }
            // Detaching keeps the recovery document ID so the next launch still
            // matches the on-disk recovery record; only the file link is dropped.
            let restoredDocument = DocumentSession(
                id: recovery.documentID,
                fileReference: detachesRecoveryFromFile ? nil : fileReference,
                displayName: detachesRecoveryFromFile
                    ? "Untitled"
                    : session?.displayName ?? "Untitled",
                saveState: restoredSaveState,
                hasUnsavedChanges: true,
                generation: generationBeforeReplacement(
                    recovery.documentGeneration ?? session?.documentGeneration
                ),
                lastSavedHash: detachesRecoveryFromFile ? nil : recovery.baseDiskHash,
                lastKnownDiskMTime: detachesRecoveryFromFile ? nil : recovery.baseDiskMTime,
                lineEnding: recovery.lineEnding,
                selection: recovery.selection,
                scrollOffsetY: recovery.scrollOffsetY
            )
            restoredDocument.replaceEntireContents(
                recovery.unsavedText,
                source: .sessionRestore,
                selection: recovery.selection
            )
            replaceCurrentDocument(with: restoredDocument)
            if detachesRecoveryFromFile {
                publishDetachedRecoveryBanner(
                    path: recovery.filePathHint ?? session?.displayName ?? "the original file"
                )
            }
            return source
        case .file(let session, let reference):
            let openedFile: FileOpenResult
            do {
                openedFile = try await files.open(reference)
            } catch {
                AppLog.files.error(
                    "Launch reopen failed: \(String(describing: type(of: error)), privacy: .public); path: \(reference.pathHint, privacy: .private)"
                )
                replaceCurrentDocument(with: DocumentSession())
                publishUnavailableFileBanner(displayName: session.displayName)
                return .empty
            }
            let restoredDocument = DocumentSession(
                id: session.documentID,
                fileReference: reference,
                displayName: openedFile.displayName,
                saveState: .clean,
                hasUnsavedChanges: false,
                generation: generationBeforeReplacement(session.documentGeneration),
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
            replaceCurrentDocument(with: restoredDocument)
            return source
        case .empty:
            replaceCurrentDocument(with: DocumentSession())
            return source
        }
    }

    private func publishUnavailableFileBanner(displayName: String) {
        banner = ErrorBanner(
            id: UUID(),
            message: "Scratchpad couldn't reopen \(displayName). It may have been moved or deleted.",
            actions: [.reselectFile, .dismiss]
        )
    }

    private func publishDetachedRecoveryBanner(path: String) {
        AppLog.bookmarks.error(
            "Recovered text detached from its file; path: \(path, privacy: .private)"
        )
        banner = ErrorBanner(
            id: UUID(),
            message: "Scratchpad couldn't reconnect your unsaved text to \(path). It's open as Untitled; use Save As to keep it.",
            actions: [.saveAs, .dismiss]
        )
    }

    // MARK: - Operation State Machine

    private struct OperationDependencies {
        let services: ApplicationServices
        let recovery: RecoveryCoordinator
    }

    private struct DocumentOperationBoundary: Equatable {
        let documentID: UUID
        let generation: Int
    }

    private func receiveExternalFileStatus(
        documentID: UUID,
        generation: Int,
        status: ExternalFileStatus,
        services: ApplicationServices
    ) async {
        guard document.id == documentID else { return }
        do {
            try await waitForIdleOperation()
        } catch {
            return
        }
        guard !Task.isCancelled,
              document.id == documentID else { return }

        let recovery = resolvedRecoveryCoordinator(services: services)
        switch status {
        case .unchanged:
            return
        case .missing:
            // The monitor repeats unchanged statuses every second. Acting on a
            // repeat would restart the recovery debounce before it can fire.
            guard document.saveState != .deleted else { return }
            document.markDeleted()
            recovery.scheduleRecovery(for: document)
            if let reference = document.fileReference {
                publishFileBanner(FileServiceError.missing, path: reference.pathHint)
            }
        case .readOnly:
            document.markReadOnly()
            if let reference = document.fileReference {
                publishFileBanner(FileServiceError.readOnly, path: reference.pathHint)
            }
        case .accessRequiresReselection:
            document.markReadOnly()
            if let reference = document.fileReference {
                publishFileBanner(
                    FileServiceError.accessRequiresReselection,
                    path: reference.pathHint
                )
            }
        case .changed:
            if document.hasUnsavedChanges {
                guard document.saveState != .conflicted else { return }
                document.markConflicted()
                recovery.scheduleRecovery(for: document)
                return
            }
            guard document.generation == generation,
                  let reference = document.fileReference else { return }
            let boundary = currentDocumentBoundary()
            operationState = .opening(reference)
            defer { finishOperation() }
            do {
                let result = try await services.files.open(reference)
                try Task.checkCancellation()
                guard document.id == boundary.documentID else { return }
                guard document.generation == boundary.generation,
                      !document.hasUnsavedChanges else {
                    document.markConflicted()
                    recovery.scheduleRecovery(for: document)
                    return
                }
                document.applyOpenedFile(result, source: .confirmedDiskReload)
                scheduleMetrics(for: document)
            } catch is CancellationError {
                return
            } catch let error as FileServiceError {
                guard !Task.isCancelled else { return }
                switch error {
                case .missing:
                    document.markDeleted()
                    recovery.scheduleRecovery(for: document)
                case .readOnly, .accessRequiresReselection:
                    document.markReadOnly()
                default:
                    break
                }
                publishFileBanner(error, path: reference.pathHint)
            } catch {
                guard !Task.isCancelled else { return }
                publishFileBanner(error, path: reference.pathHint)
            }
        }
    }

    private func waitForIdleOperation() async throws {
        while operationState != .idle {
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if operationState == .idle {
                        continuation.resume()
                    } else {
                        idleOperationWaiters[waiterID] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelIdleOperationWaiter(waiterID)
                }
            }
        }
        try Task.checkCancellation()
    }

    private func cancelIdleOperationWaiter(_ waiterID: UUID) {
        idleOperationWaiters.removeValue(forKey: waiterID)?.resume(
            throwing: CancellationError()
        )
    }

    private func finishOperation() {
        operationState = .idle
        let waiters = Array(idleOperationWaiters.values)
        idleOperationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func replaceCurrentDocument(with replacement: DocumentSession) {
        externalChangeMonitor?.stop()
        document = replacement
        scheduleMetrics(for: replacement)
    }

    private func scheduleMetrics(for document: DocumentSession) {
        let snapshot = document.snapshot()
        metricsCoordinator.schedule(
            documentID: snapshot.documentID,
            generation: snapshot.generation,
            text: snapshot.text,
            countsWhitespace: settings.snapshot.countsWhitespace
        ) { [weak self] documentID, generation, metrics in
            self?.receiveMetrics(
                documentID: documentID,
                generation: generation,
                metrics: metrics
            )
        }
    }

    private func observeMetricsSettings() {
        withObservationTracking {
            _ = settings.snapshot.countsWhitespace
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeMetricsSettings()
                self.scheduleMetrics(for: self.document)
            }
        }
    }

    func receiveMetrics(
        documentID: UUID,
        generation: Int,
        metrics: DocumentMetrics
    ) {
        guard document.id == documentID,
              document.generation == generation else { return }
        self.metrics = metrics
    }

    private func persistAndReplaceCurrentDocument(
        with replacement: DocumentSession,
        using dependencies: OperationDependencies
    ) async {
        let boundary = currentDocumentBoundary()
        do {
            try await dependencies.recovery.flushSession(
                for: replacement,
                windowFrame: windowFrameProvider(),
                didCloseCleanly: false
            )
        } catch {
            publishPersistenceBanner(error)
            if document.id == boundary.documentID,
               document.hasUnsavedChanges {
                _ = await preserveLatestDocumentState(
                    documentID: boundary.documentID,
                    using: dependencies
                )
            } else {
                _ = await revalidate(boundary, using: dependencies)
            }
            return
        }
        guard await revalidate(boundary, using: dependencies) else { return }
        replaceCurrentDocument(with: replacement)
    }

    private func operationDependencies() -> OperationDependencies? {
        do {
            let services = try resolvedServices()
            return OperationDependencies(
                services: services,
                recovery: resolvedRecoveryCoordinator(services: services)
            )
        } catch {
            publishPersistenceBanner(error)
            return nil
        }
    }

    private func approveReplacement(
        _ replacement: PendingReplacement,
        dependencies: OperationDependencies
    ) async -> Bool {
        let boundary = currentDocumentBoundary()
        guard document.hasUnsavedChanges else {
            let deleted = await deleteRecovery(
                documentID: document.id,
                using: dependencies
            )
            guard await revalidate(boundary, using: dependencies) else { return false }
            return deleted
        }
        let resolution = await decisionCoordinator.request(.replaceCurrentDocument(replacement))
        guard await revalidate(boundary, using: dependencies) else { return false }
        switch resolution {
        case .save:
            let saved = await performSave(document.snapshot(), using: dependencies)
            guard await revalidate(boundary, using: dependencies) else { return false }
            return saved && !document.hasUnsavedChanges
        case .discard:
            let deleted = await deleteRecovery(
                documentID: document.id,
                using: dependencies
            )
            guard await revalidate(boundary, using: dependencies) else { return false }
            return deleted
        case .cancel:
            requestEditorFocus()
            return false
        default:
            requestEditorFocus()
            return false
        }
    }

    private func requestExit(
        _ decision: DocumentDecision,
        operation: DocumentOperationState
    ) async -> Bool {
        guard operationState == .idle else { return false }
        operationState = operation
        defer { finishOperation() }
        guard let dependencies = operationDependencies() else { return false }

        if document.hasUnsavedChanges {
            let decisionBoundary = currentDocumentBoundary()
            guard decisionCoordinator.begin(decision) else { return false }
            if recoveryCleanupRequiredDocumentID == document.id {
                recoveryCleanupRequiredDocumentID = nil
            }
            guard await flushRecovery(using: dependencies.recovery) else {
                decisionCoordinator.cancelPending()
                return false
            }
            guard await revalidate(decisionBoundary, using: dependencies) else {
                decisionCoordinator.cancelPending()
                return false
            }
            let resolution = await decisionCoordinator.waitForResolution()
            guard await revalidate(decisionBoundary, using: dependencies) else { return false }
            switch resolution {
            case .save:
                let saved = await performSave(document.snapshot(), using: dependencies)
                guard await revalidate(decisionBoundary, using: dependencies),
                      saved,
                      !document.hasUnsavedChanges else { return false }
            case .discard:
                let deleted = await deleteRecovery(
                    documentID: document.id,
                    using: dependencies
                )
                guard await revalidate(decisionBoundary, using: dependencies),
                      deleted else { return false }
            case .cancel:
                requestEditorFocus()
                return false
            default:
                requestEditorFocus()
                return false
            }
        } else {
            if recoveryCleanupRequiredDocumentID == document.id {
                recoveryCleanupRequiredDocumentID = nil
            }
            guard await flushRecovery(using: dependencies.recovery) else { return false }
        }

        let nonCleanBoundary = currentDocumentBoundary()
        do {
            try await dependencies.recovery.flushSession(
                for: document,
                windowFrame: windowFrameProvider(),
                didCloseCleanly: false
            )
        } catch {
            publishPersistenceBanner(error)
            _ = await revalidate(nonCleanBoundary, using: dependencies)
            return false
        }
        guard await revalidate(nonCleanBoundary, using: dependencies) else { return false }

        let sessionBoundary = currentDocumentBoundary()
        do {
            try await dependencies.recovery.flushSession(
                for: document,
                windowFrame: windowFrameProvider(),
                didCloseCleanly: true
            )
        } catch {
            publishPersistenceBanner(error)
            _ = await revalidate(sessionBoundary, using: dependencies)
            return false
        }
        return await revalidate(sessionBoundary, using: dependencies)
    }

    private func applyOpenedFile(
        _ result: FileOpenResult,
        using dependencies: OperationDependencies
    ) async {
        let openedDocument = DocumentSession(
            fileReference: result.reference,
            displayName: result.displayName,
            saveState: .clean,
            hasUnsavedChanges: false,
            lastSavedHash: result.contentHash,
            lastKnownDiskMTime: result.modificationDate,
            lineEnding: result.lineEnding
        )
        openedDocument.replaceEntireContents(
            result.text,
            source: .fileOpen,
            selection: nil
        )
        await persistAndReplaceCurrentDocument(
            with: openedDocument,
            using: dependencies
        )
        guard document === openedDocument else { return }
        startExternalChangeMonitoring()
    }

    private func performSave(
        _ snapshot: DocumentSnapshot,
        using dependencies: OperationDependencies
    ) async -> Bool {
        guard let reference = snapshot.fileReference else {
            return await performSaveAs(snapshot, using: dependencies)
        }

        if snapshot.saveState == .deleted {
            guard await decisionCoordinator.request(.recreateDeletedFile) == .recreate else {
                requestEditorFocus()
                return false
            }
            return await performUnconditionalSave(
                snapshot,
                to: reference,
                using: dependencies
            )
        }

        guard await flushRecovery(
            snapshot,
            using: dependencies.recovery
        ) else { return false }

        do {
            let result = try await dependencies.services.files.save(snapshot)
            return await applySaveResult(
                result,
                initiatedBy: snapshot,
                using: dependencies
            )
        } catch let error as FileServiceError {
            switch error {
            case let .conflict(diskHash, diskModificationDate):
                document.markConflicted()
                let context = ConflictContext(
                    documentID: snapshot.documentID,
                    initiatingGeneration: snapshot.generation,
                    fileReference: reference,
                    baseHash: snapshot.lastSavedHash,
                    diskHash: diskHash,
                    diskModificationDate: diskModificationDate
                )
                return await resolveConflict(
                    context,
                    snapshot: snapshot,
                    dependencies: dependencies
                )
            case .missing:
                document.markDeleted()
                dependencies.recovery.scheduleRecovery(for: document)
                guard await decisionCoordinator.request(.recreateDeletedFile) == .recreate else {
                    requestEditorFocus()
                    return false
                }
                return await performUnconditionalSave(
                    snapshot,
                    to: reference,
                    using: dependencies
                )
            case .readOnly:
                document.markReadOnly()
                publishFileBanner(
                    error,
                    path: reference.pathHint,
                    retryOperation: .saveCurrentDocument
                )
                return false
            default:
                publishFileBanner(
                    error,
                    path: reference.pathHint,
                    retryOperation: .saveCurrentDocument
                )
                return false
            }
        } catch {
            publishFileBanner(
                error,
                path: reference.pathHint,
                retryOperation: .saveCurrentDocument
            )
            return false
        }
    }

    private func resolveConflict(
        _ context: ConflictContext,
        snapshot: DocumentSnapshot,
        dependencies: OperationDependencies
    ) async -> Bool {
        switch await decisionCoordinator.request(.resolveConflict(context)) {
        case .overwrite:
            return await performUnconditionalSave(
                snapshot,
                to: context.fileReference,
                using: dependencies
            )
        case .reloadFromDisk:
            let reloadBoundary = DocumentOperationBoundary(
                documentID: context.documentID,
                generation: context.initiatingGeneration
            )
            guard await revalidate(reloadBoundary, using: dependencies) else { return false }
            guard await flushRecovery(using: dependencies.recovery) else { return false }
            guard await revalidate(reloadBoundary, using: dependencies) else { return false }
            do {
                let result = try await dependencies.services.files.open(context.fileReference)
                guard await revalidate(reloadBoundary, using: dependencies) else { return false }
                document.applyOpenedFile(result, source: .confirmedDiskReload)
                scheduleMetrics(for: document)
            } catch {
                publishFileBanner(error, path: context.fileReference.pathHint)
            }
            return false
        case .saveAs:
            return await performSaveAs(snapshot, using: dependencies)
        case .cancel:
            requestEditorFocus()
            return false
        default:
            requestEditorFocus()
            return false
        }
    }

    private func performSaveAs(
        _ snapshot: DocumentSnapshot,
        using dependencies: OperationDependencies
    ) async -> Bool {
        guard let panelProvider,
              let selectedURL = await panelProvider.selectSaveDestination(
                suggestedName: document.displayName
              ) else { return false }

        guard await flushRecovery(
            snapshot,
            using: dependencies.recovery
        ) else { return false }

        do {
            let result = try await dependencies.services.files.saveAs(
                snapshot,
                toSelectedURL: selectedURL
            )
            guard await flushRecovery(
                snapshot.recoveryRecord(verifiedSaveAs: result),
                using: dependencies.recovery
            ) else {
                if document.id == snapshot.documentID,
                   document.generation != snapshot.generation {
                    _ = await preserveLatestDocumentState(
                        documentID: snapshot.documentID,
                        using: dependencies
                    )
                }
                return false
            }
            return await applySaveResult(
                result,
                initiatedBy: snapshot,
                using: dependencies
            )
        } catch {
            if document.id == snapshot.documentID,
               document.generation != snapshot.generation {
                _ = await preserveLatestDocumentState(
                    documentID: snapshot.documentID,
                    using: dependencies
                )
            }
            publishFileBanner(error, path: selectedURL.path)
            return false
        }
    }

    private func performUnconditionalSave(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference,
        using dependencies: OperationDependencies
    ) async -> Bool {
        let changesAssociation = snapshot.fileReference != reference
        let pendingSaveAs = changesAssociation
            ? PendingSaveAsRecord(
                destinationFileReferenceID: reference.bookmarkID,
                destinationPathHint: reference.pathHint,
                expectedContentHash: ContentHash.sha256(snapshot.persistedBytes)
            )
            : nil
        guard await flushRecovery(
            snapshot,
            pendingSaveAs: pendingSaveAs,
            using: dependencies.recovery
        ) else { return false }
        do {
            let result = try await dependencies.services.files.saveAs(snapshot, to: reference)
            if changesAssociation {
                guard await flushRecovery(
                    snapshot.recoveryRecord(verifiedSaveAs: result),
                    using: dependencies.recovery
                ) else {
                    if document.id == snapshot.documentID,
                       document.generation != snapshot.generation {
                        _ = await preserveLatestDocumentState(
                            documentID: snapshot.documentID,
                            pendingSaveAs: pendingSaveAs,
                            using: dependencies
                        )
                    }
                    return false
                }
            }
            return await applySaveResult(
                result,
                initiatedBy: snapshot,
                using: dependencies
            )
        } catch {
            if document.id == snapshot.documentID,
               document.generation != snapshot.generation {
                _ = await preserveLatestDocumentState(
                    documentID: snapshot.documentID,
                    using: dependencies
                )
            } else if changesAssociation {
                _ = await flushRecovery(
                    snapshot,
                    using: dependencies.recovery
                )
            }
            publishFileBanner(error, path: reference.pathHint)
            return false
        }
    }

    private func applySaveResult(
        _ result: FileSaveResult,
        initiatedBy snapshot: DocumentSnapshot,
        using dependencies: OperationDependencies
    ) async -> Bool {
        guard document.id == snapshot.documentID,
              result.documentID == snapshot.documentID,
              result.initiatingGeneration == snapshot.generation else { return false }

        let matchesGeneration = document.generation == snapshot.generation
        document.adoptVerifiedSave(result, markClean: matchesGeneration)
        startExternalChangeMonitoring()
        if matchesGeneration {
            let boundary = currentDocumentBoundary()
            do {
                try await dependencies.recovery.flushSession(
                    for: document,
                    windowFrame: windowFrameProvider(),
                    didCloseCleanly: false
                )
            } catch {
                publishPersistenceBanner(error)
                _ = await revalidate(boundary, using: dependencies)
                return false
            }
            guard await revalidate(boundary, using: dependencies) else { return false }
            recoveryCleanupRequiredDocumentID = snapshot.documentID
            return await deleteRecovery(
                documentID: snapshot.documentID,
                using: dependencies
            )
        }
        return await preserveLatestDocumentState(
            documentID: snapshot.documentID,
            using: dependencies
        )
    }

    private func flushRecovery(using coordinator: RecoveryCoordinator) async -> Bool {
        do {
            try await coordinator.flushRecovery(for: document)
            return true
        } catch {
            publishPersistenceBanner(error)
            return false
        }
    }

    private func flushRecovery(
        _ snapshot: DocumentSnapshot,
        pendingSaveAs: PendingSaveAsRecord? = nil,
        using coordinator: RecoveryCoordinator
    ) async -> Bool {
        do {
            try await coordinator.flushRecovery(
                snapshot.recoveryRecord(pendingSaveAs: pendingSaveAs)
            )
            return true
        } catch {
            publishPersistenceBanner(error)
            return false
        }
    }

    private func flushRecovery(
        _ record: RecoveryRecord,
        using coordinator: RecoveryCoordinator
    ) async -> Bool {
        do {
            try await coordinator.flushRecovery(record)
            return true
        } catch {
            publishPersistenceBanner(error)
            return false
        }
    }

    private func deleteRecovery(
        documentID: UUID,
        using dependencies: OperationDependencies
    ) async -> Bool {
        dependencies.recovery.cancelRecovery(documentID: documentID)
        do {
            try await dependencies.services.repository.deleteRecovery(documentID: documentID)
            if recoveryCleanupRequiredDocumentID == documentID {
                recoveryCleanupRequiredDocumentID = nil
            }
            return true
        } catch {
            publishPersistenceBanner(error)
            return false
        }
    }

    private func currentDocumentBoundary() -> DocumentOperationBoundary {
        DocumentOperationBoundary(
            documentID: document.id,
            generation: document.generation
        )
    }

    private func revalidate(
        _ boundary: DocumentOperationBoundary,
        using dependencies: OperationDependencies
    ) async -> Bool {
        guard document.id == boundary.documentID else { return false }
        guard document.generation != boundary.generation else { return true }
        _ = await preserveLatestDocumentState(
            documentID: boundary.documentID,
            using: dependencies
        )
        requestEditorFocus()
        return false
    }

    private func preserveLatestDocumentState(
        documentID: UUID,
        pendingSaveAs: PendingSaveAsRecord? = nil,
        using dependencies: OperationDependencies
    ) async -> Bool {
        while document.id == documentID {
            let generation = document.generation
            if recoveryCleanupRequiredDocumentID == documentID {
                recoveryCleanupRequiredDocumentID = nil
            }
            guard await flushRecovery(
                document.snapshot(),
                pendingSaveAs: pendingSaveAs,
                using: dependencies.recovery
            ) else { return false }
            do {
                try await dependencies.recovery.flushSession(
                    for: document,
                    windowFrame: windowFrameProvider(),
                    didCloseCleanly: false
                )
            } catch {
                publishPersistenceBanner(error)
                return false
            }
            guard document.id == documentID,
                  document.generation != generation else {
                return document.id == documentID
            }
        }
        return false
    }

    // MARK: - Error Presentation

    private func publishFileBanner(
        _ error: Error,
        path: String,
        retryOperation: BannerRetryOperation? = nil
    ) {
        let category: String
        let message: String
        let actions: [BannerAction]
        switch error as? FileServiceError {
        case .missing:
            category = "FileServiceError.missing"
            message = "The file no longer exists. Your text is still open."
            actions = [.saveAs, .dismiss]
        case .readOnly:
            category = "FileServiceError.readOnly"
            message = "The file is read only. Save your text to another location."
            actions = [.saveAs, .dismiss]
        case .accessRequiresReselection:
            category = "FileServiceError.accessRequiresReselection"
            message = "Scratchpad needs permission to access this file again."
            actions = [.reselectFile, .dismiss]
        case .invalidUTF8:
            category = "FileServiceError.invalidUTF8"
            message = "Scratchpad can open UTF-8 text files only."
            actions = [.dismiss]
        case .verificationFailed:
            category = "FileServiceError.verificationFailed"
            message = "The save could not be verified. Your text remains open."
            actions = retryOperation.map { [.retry($0), .saveAs, .dismiss] }
                ?? [.saveAs, .dismiss]
        case let typed?:
            category = "FileServiceError.\(String(describing: typed))"
            message = "The file operation failed. Your text remains open."
            actions = retryOperation.map { [.retry($0), .saveAs, .dismiss] }
                ?? [.saveAs, .dismiss]
        case nil:
            category = String(describing: type(of: error))
            message = "The file operation failed. Your text remains open."
            actions = retryOperation.map { [.retry($0), .saveAs, .dismiss] }
                ?? [.saveAs, .dismiss]
        }
        AppLog.files.error(
            "File operation failed: \(category, privacy: .public); path: \(path, privacy: .private)"
        )
        banner = ErrorBanner(id: UUID(), message: message, actions: actions)
    }

    private func publishBookmarkBanner(_ error: Error, path: String) {
        let category: String
        switch error as? BookmarkStoreError {
        case .reselectionRequired: category = "BookmarkStoreError.reselectionRequired"
        case .accessDenied: category = "BookmarkStoreError.accessDenied"
        case .inactiveToken: category = "BookmarkStoreError.inactiveToken"
        case .bookmarkInUse: category = "BookmarkStoreError.bookmarkInUse"
        case .quarantineFailed: category = "BookmarkStoreError.quarantineFailed"
        case nil: category = String(describing: type(of: error))
        }
        AppLog.bookmarks.error(
            "Bookmark operation failed: \(category, privacy: .public); path: \(path, privacy: .private)"
        )
        banner = ErrorBanner(
            id: UUID(),
            message: "Scratchpad couldn't retain access to that file.",
            actions: [.reselectFile, .dismiss]
        )
    }

    private func publishPersistenceBanner(_ error: Error) {
        let category: String
        switch error as? SessionRepositoryError {
        case .invalidRecord: category = "SessionRepositoryError.invalidRecord"
        case .quarantineFailed: category = "SessionRepositoryError.quarantineFailed"
        case .unsupportedSchema: category = "SessionRepositoryError.unsupportedSchema"
        case nil: category = String(describing: type(of: error))
        }
        AppLog.persistence.error(
            "Persistence operation failed: \(category, privacy: .public)"
        )
        banner = ErrorBanner(
            id: UUID(),
            message: "Scratchpad couldn't update recovery safely. Your text remains open.",
            actions: [.retry(.preserveCurrentDocument), .openRecoveryFolder, .dismiss]
        )
    }

    private func generationBeforeReplacement(_ generation: Int?) -> Int {
        guard let generation else { return 0 }
        return DocumentGeneration.previous(before: generation)
    }

    private func nextPersistedGeneration(_ first: Int?, _ second: Int?) -> Int? {
        let current: Int
        switch (first, second) {
        case let (first?, second?):
            current = first == second
                || DocumentGeneration.isNewer(first, than: second)
                ? first
                : second
        case let (first?, nil):
            current = first
        case let (nil, second?):
            current = second
        case (nil, nil):
            current = 0
        }
        guard current >= 0 else { return nil }
        return DocumentGeneration.next(after: current)
    }
}

private extension NSView {
    func firstDescendant<View: NSView>(of type: View.Type) -> View? {
        if let matching = self as? View { return matching }
        for subview in subviews {
            if let matching = subview.firstDescendant(of: type) { return matching }
        }
        return nil
    }
}
