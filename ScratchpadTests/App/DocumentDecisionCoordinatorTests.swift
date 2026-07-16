import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import Scratchpad

@MainActor
final class DocumentDecisionCoordinatorTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 820, height: 640)

    func testReentrantOnBeginResolutionCompletesOuterRequest() async {
        var coordinator: DocumentDecisionCoordinator!
        var observedResolution: DocumentDecisionResolution?
        coordinator = DocumentDecisionCoordinator { _ in
            coordinator.resolvePending(with: .save)
        }

        let request = Task {
            observedResolution = await coordinator.request(.closeWindow)
        }
        guard await waitUntil({ observedResolution != nil }) else {
            request.cancel()
            return
        }

        await request.value
        XCTAssertEqual(observedResolution, .save)
        XCTAssertNil(coordinator.pending)
    }

    func testReentrantOnBeginCannotReplaceOuterPendingDecision() async {
        var coordinator: DocumentDecisionCoordinator!
        var callbackCount = 0
        var nestedBeginResult: Bool?
        coordinator = DocumentDecisionCoordinator { _ in
            callbackCount += 1
            if callbackCount == 1 {
                nestedBeginResult = coordinator.begin(.terminateApplication)
            }
        }

        let request = Task { await coordinator.request(.closeWindow) }
        guard await waitUntil({ nestedBeginResult != nil && coordinator.pending != nil }) else {
            request.cancel()
            return
        }

        XCTAssertEqual(nestedBeginResult, false)
        if case .closeWindow? = coordinator.pending {
            // The outer decision remains authoritative.
        } else {
            XCTFail("Reentrant begin replaced the outer pending decision")
        }
        coordinator.resolvePending(with: .discard)
        let resolution = await request.value
        XCTAssertEqual(resolution, .discard)
    }

    func testResolvedDecisionCanImmediatelyPublishTheNextDecision() async {
        let coordinator = DocumentDecisionCoordinator()
        let first = Task { await coordinator.request(.closeWindow) }
        guard await waitUntil({ coordinator.hasActiveWaiter }) else {
            first.cancel()
            return
        }
        coordinator.resolvePending(with: .cancel)

        let second = Task { await coordinator.request(.terminateApplication) }
        guard await waitUntil({ coordinator.hasActiveWaiter }) else {
            second.cancel()
            return
        }
        if case .terminateApplication? = coordinator.pending {
            // A sheet observing pending can transition directly to this decision.
        } else {
            XCTFail("The next decision was not published")
        }
        coordinator.resolvePending(with: .save)

        let firstResolution = await first.value
        let secondResolution = await second.value
        XCTAssertEqual(firstResolution, .cancel)
        XCTAssertEqual(secondResolution, .save)
    }

    func testCoordinatorAllowsOnlyOnePendingDecision() async {
        let coordinator = DocumentDecisionCoordinator()
        let first = Task { await coordinator.request(.closeWindow) }
        guard await waitUntil({ coordinator.pending != nil }) else {
            first.cancel()
            return
        }

        let second = await coordinator.request(.terminateApplication)
        XCTAssertEqual(second, .cancel)
        XCTAssertNotNil(coordinator.pending)

        coordinator.resolvePending(with: .discard)
        let firstResolution = await first.value
        XCTAssertEqual(firstResolution, .discard)
        XCTAssertNil(coordinator.pending)
        coordinator.resolvePending(with: .save)
        XCTAssertNil(coordinator.pending)
    }

    func testCancellationWhileWaitingClearsOnlyTheMatchingWaiter() async {
        let coordinator = DocumentDecisionCoordinator()
        XCTAssertTrue(coordinator.begin(.closeWindow))
        let cancelled = Task { await coordinator.waitForResolution() }
        guard await waitUntil({ coordinator.hasActiveWaiter }) else {
            cancelled.cancel()
            return
        }

        cancelled.cancel()
        let cancelledResolution = await cancelled.value
        XCTAssertEqual(cancelledResolution, .cancel)
        XCTAssertNil(coordinator.pending)

        let replacement = Task { await coordinator.request(.terminateApplication) }
        guard await waitUntil({ coordinator.hasActiveWaiter }) else {
            replacement.cancel()
            return
        }
        coordinator.resolvePending(with: .save)
        let replacementResolution = await replacement.value
        XCTAssertEqual(replacementResolution, .save)
    }

    func testSecondWaitAttemptCannotOverwriteSuspendedWaiter() async {
        let coordinator = DocumentDecisionCoordinator()
        XCTAssertTrue(coordinator.begin(.closeWindow))
        let first = Task { await coordinator.waitForResolution() }
        guard await waitUntil({ coordinator.hasActiveWaiter }) else {
            first.cancel()
            return
        }

        let secondResolution = await coordinator.waitForResolution()
        XCTAssertEqual(secondResolution, .cancel)
        XCTAssertNotNil(coordinator.pending)
        coordinator.resolvePending(with: .discard)
        let firstResolution = await first.value
        XCTAssertEqual(firstResolution, .discard)
        XCTAssertNil(coordinator.pending)
    }

    func testRepeatedEarlyResolutionKeepsFirstAcceptedResolution() async {
        let coordinator = DocumentDecisionCoordinator()
        XCTAssertTrue(coordinator.begin(.closeWindow))

        coordinator.resolvePending(with: .save)
        coordinator.resolvePending(with: .discard)

        let resolution = await coordinator.waitForResolution()
        XCTAssertEqual(resolution, .save)
        XCTAssertNil(coordinator.pending)
    }

    func testDuplicateBeginAndRequestCannotReplacePendingDecision() async {
        let coordinator = DocumentDecisionCoordinator()
        XCTAssertTrue(coordinator.begin(.closeWindow))
        XCTAssertFalse(coordinator.begin(.terminateApplication))
        let duplicateRequestResolution = await coordinator.request(.terminateApplication)
        XCTAssertEqual(duplicateRequestResolution, .cancel)

        coordinator.resolvePending(with: .discard)
        let resolution = await coordinator.waitForResolution()
        XCTAssertEqual(resolution, .discard)
        XCTAssertNil(coordinator.pending)
    }

    func testCancelLeavesDocumentAndRecoveryUnchanged() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake()
        let document = makeEditedDocument(text: "preserve me")
        document.updateSelection(TextSelection(location: 3, length: 4))
        let model = makeModel(document: document, repository: repository, files: files)
        let before = document.snapshot()

        let request = Task { await model.requestNewDocument() }
        guard await waitUntil({ model.pendingDecision != nil }) else {
            request.cancel()
            return
        }
        model.resolvePendingDecision(with: .cancel)
        await request.value

        XCTAssertTrue(model.document === document)
        assertSnapshotsEqual(model.document.snapshot(), before)
        let deletedDocumentIDs = await repository.deletedDocumentIDs
        XCTAssertEqual(deletedDocumentIDs, [])
        XCTAssertEqual(model.operationState, .idle)

        let restoringRepository = OperationRepositoryFake()
        let restoringDocument = DocumentSession()
        let restoringModel = makeModel(
            document: restoringDocument,
            launchState: .restoring,
            repository: restoringRepository,
            files: ControllableFileServiceFake()
        )
        let closeDuringRestore = await restoringModel.requestClose()
        let restoringSessionWriteCount = await restoringRepository.sessionWriteCount
        XCTAssertFalse(closeDuringRestore)
        XCTAssertTrue(restoringModel.document === restoringDocument)
        XCTAssertEqual(restoringSessionWriteCount, 0)
        XCTAssertFalse(AppCommands.operationsEnabled(for: restoringModel))
        XCTAssertTrue(AppCommands.operationsEnabled(for: model))
    }

    func testSaveAndCloseWaitsForVerifiedSaveResult() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake(saveSuspended: true)
        let document = makeEditedDocument(text: "save then close")
        let model = makeModel(document: document, repository: repository, files: files)
        let closeCount = LockedCounter()

        let close = Task {
            if await model.requestClose() { closeCount.increment() }
        }
        guard await waitUntil({ model.pendingDecision != nil }) else {
            close.cancel()
            return
        }
        model.resolvePendingDecision(with: .save)
        await files.waitForSaveCalls(1)
        XCTAssertEqual(closeCount.value, 0)

        await files.resumeSaveSuccessfully()
        await close.value
        XCTAssertEqual(closeCount.value, 1)
        XCTAssertFalse(document.hasUnsavedChanges)
        let deletedDocumentIDs = await repository.deletedDocumentIDs
        XCTAssertEqual(deletedDocumentIDs, [document.id])
    }

    func testFailedSaveCancelsCloseAndKeepsDocumentEdited() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake(saveSuspended: true)
        let document = makeEditedDocument(text: "must remain")
        let model = makeModel(document: document, repository: repository, files: files)
        let closeCount = LockedCounter()

        let close = Task {
            if await model.requestClose() { closeCount.increment() }
        }
        guard await waitUntil({ model.pendingDecision != nil }) else {
            close.cancel()
            return
        }
        model.resolvePendingDecision(with: .save)
        await files.waitForSaveCalls(1)
        await files.resumeSave(throwing: .writeFailed)
        await close.value

        XCTAssertEqual(closeCount.value, 0)
        XCTAssertTrue(document.hasUnsavedChanges)
        XCTAssertEqual(document.saveState, .edited)
        XCTAssertNotNil(model.banner)
        let deletedDocumentIDs = await repository.deletedDocumentIDs
        XCTAssertEqual(deletedDocumentIDs, [])
    }

    func testDiscardDeletesRecoveryBeforeReplacingDocument() async {
        let events = OperationEventRecorder()
        let repository = OperationRepositoryFake(events: events)
        let files = ControllableFileServiceFake(events: events)
        let bookmarks = OperationBookmarkFake()
        let panel = OperationPanelFake(openURLs: [URL(fileURLWithPath: "/tmp/replacement.md")])
        let oldDocument = makeEditedDocument(text: "discarded draft")
        let model = makeModel(
            document: oldDocument,
            repository: repository,
            bookmarks: bookmarks,
            files: files,
            panel: panel
        )

        let open = Task { await model.requestOpen() }
        guard await waitUntil({ model.pendingDecision != nil }) else {
            open.cancel()
            return
        }
        model.resolvePendingDecision(with: .discard)
        await open.value

        XCTAssertFalse(model.document === oldDocument)
        XCTAssertEqual(model.document.storage.string, "opened text")
        let recorded = await events.events
        XCTAssertTrue(recorded.contains("delete:\(oldDocument.id)"))

        let failedRepository = OperationRepositoryFake()
        let failedDocument = makeEditedDocument(text: "still recoverable")
        let failedModel = makeModel(
            document: failedDocument,
            repository: failedRepository,
            bookmarks: OperationBookmarkFake(),
            files: ControllableFileServiceFake(openError: .invalidUTF8),
            panel: OperationPanelFake(openURLs: [URL(fileURLWithPath: "/tmp/invalid.md")])
        )
        var failedOpenDidFinish = false
        let failedOpen = Task {
            await failedModel.requestOpen()
            failedOpenDidFinish = true
        }
        guard await waitUntilOrTimeout({
            failedModel.pendingDecision != nil || failedOpenDidFinish
        }) else {
            XCTFail("Timed out waiting for the failed-open operation")
            failedOpen.cancel()
            return
        }
        if failedModel.pendingDecision != nil {
            failedModel.resolvePendingDecision(with: .discard)
        }
        await failedOpen.value

        let failedDeletedDocumentIDs = await failedRepository.deletedDocumentIDs
        let failedRecoveryWrites = await failedRepository.recoveryWrites
        XCTAssertTrue(failedModel.document === failedDocument)
        XCTAssertEqual(failedDocument.storage.string, "still recoverable")
        XCTAssertEqual(failedDeletedDocumentIDs, [])
        XCTAssertEqual(failedRecoveryWrites.last?.unsavedText, "still recoverable")
    }

    func testGenerationChangeDuringSaveRemainsEditedAndReschedulesRecovery() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake(saveSuspended: true)
        let document = makeEditedDocument(text: "first generation")
        let model = makeModel(document: document, repository: repository, files: files)

        let save = Task { await model.save() }
        await files.waitForSaveCalls(1)
        document.storage.setAttributedString(NSAttributedString(string: "newer generation"))
        document.noteUserEdit()
        await files.resumeSaveSuccessfully()

        let saved = await save.value
        XCTAssertTrue(saved)
        await repository.waitForRecoveryWrites(1)
        XCTAssertTrue(document.hasUnsavedChanges)
        XCTAssertEqual(document.saveState, .edited)
        XCTAssertEqual(document.lastSavedHash, "verified-hash")
        let deletedDocumentIDs = await repository.deletedDocumentIDs
        let recoveryWrites = await repository.recoveryWrites
        XCTAssertEqual(deletedDocumentIDs, [])
        XCTAssertEqual(recoveryWrites.last?.unsavedText, "newer generation")

        let cleanupRepository = OperationRepositoryFake(deleteFailures: 2)
        let cleanupClock = SuspendingRecoveryClock()
        let cleanupDocument = makeEditedDocument(text: "saved generation")
        let cleanupModel = makeModel(
            document: cleanupDocument,
            repository: cleanupRepository,
            files: ControllableFileServiceFake(),
            recoveryClock: cleanupClock
        )
        let initialCleanupSave = await cleanupModel.save()
        XCTAssertFalse(initialCleanupSave)
        cleanupDocument.storage.setAttributedString(NSAttributedString(string: "new unsaved edit"))
        cleanupDocument.noteUserEdit()
        cleanupModel.handleCurrentDocumentEdit(cleanupDocument)
        await cleanupClock.waitForSleepEntries(1)

        let close = Task { await cleanupModel.requestClose() }
        let reachedPendingDecision = await waitUntilOrTimeout { cleanupModel.pendingDecision != nil }
        let cleanupRecoveryWrites = await cleanupRepository.recoveryWrites
        guard reachedPendingDecision else {
            XCTFail("Timed out waiting for the cleanup decision")
            close.cancel()
            return
        }
        XCTAssertEqual(cleanupRecoveryWrites.last?.unsavedText, "new unsaved edit")
        cleanupModel.resolvePendingDecision(with: .cancel)
        let closeResult = await close.value
        XCTAssertFalse(closeResult)
    }

    func testConflictSupportsOverwriteReloadSaveAsAndCancel() async {
        for resolution in [
            DocumentDecisionResolution.overwrite,
            .reloadFromDisk,
            .saveAs,
            .cancel
        ] {
            let repository = OperationRepositoryFake()
            let files = ControllableFileServiceFake(saveError: .conflict(
                contentHash: "disk-hash",
                modificationDate: Date(timeIntervalSince1970: 42)
            ))
            let bookmarks = OperationBookmarkFake()
            let panel = OperationPanelFake(saveURLs: [URL(fileURLWithPath: "/tmp/copy.md")])
            let document = makeEditedDocument(text: "local draft")
            let model = makeModel(
                document: document,
                repository: repository,
                bookmarks: bookmarks,
                files: files,
                panel: panel
            )

            let save = Task { await model.save() }
            guard await waitUntil({
                if case .resolveConflict = model.pendingDecision { return true }
                return false
            }) else {
                save.cancel()
                return
            }
            model.resolvePendingDecision(with: resolution)
            let result = await save.value

            switch resolution {
            case .overwrite:
                XCTAssertTrue(result)
                let references = await files.saveAsReferences
                XCTAssertEqual(references, [document.fileReference])
            case .reloadFromDisk:
                XCTAssertFalse(result)
                XCTAssertEqual(document.storage.string, "opened text")
                XCTAssertFalse(document.hasUnsavedChanges)
            case .saveAs:
                XCTAssertTrue(result)
                let referenceCount = await files.saveAsReferences.count
                XCTAssertEqual(referenceCount, 1)
                XCTAssertEqual(document.fileReference?.pathHint, "/tmp/copy.md")
            case .cancel:
                XCTAssertFalse(result)
                XCTAssertEqual(document.storage.string, "local draft")
                XCTAssertTrue(document.hasUnsavedChanges)
                let references = await files.saveAsReferences
                XCTAssertEqual(references, [])
            default:
                XCTFail("Unexpected conflict resolution")
            }
        }
    }

    func testDuplicateOpenForSameReferenceDoesNotCreateSecondOperation() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake(openSuspended: true)
        let bookmarks = OperationBookmarkFake()
        let url = URL(fileURLWithPath: "/tmp/shared.md")
        let panel = OperationPanelFake(openURLs: [url, url])
        let model = makeModel(
            document: DocumentSession(),
            repository: repository,
            bookmarks: bookmarks,
            files: files,
            panel: panel
        )

        let first = Task { await model.requestOpen() }
        await files.waitForOpenCalls(1)
        let second = Task { await model.requestOpen() }
        await bookmarks.waitForStoreSelections(2)
        await Task.yield()
        let suspendedOpenCount = await files.openCallCount
        XCTAssertEqual(suspendedOpenCount, 1)

        await files.resumeOpenSuccessfully()
        await first.value
        await second.value
        let finalOpenCount = await files.openCallCount
        XCTAssertEqual(finalOpenCount, 1)
        XCTAssertEqual(model.document.storage.string, "opened text")
    }

    func testOpenPanelAllowsOnlyMdMarkdownMdownAndTxt() {
        let panel = FilePanelProvider.makeOpenPanel()

        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertEqual(Set(FilePanelProvider.allowedFileExtensions), Set(["md", "markdown", "mdown", "txt"]))
        for fileExtension in FilePanelProvider.allowedFileExtensions {
            XCTAssertTrue(FilePanelProvider.allowsOpenURL(URL(fileURLWithPath: "/tmp/file.\(fileExtension)")))
        }
        XCTAssertFalse(FilePanelProvider.allowsOpenURL(URL(fileURLWithPath: "/tmp/file.rtf")))
        XCTAssertFalse(FilePanelProvider.allowsOpenURL(URL(fileURLWithPath: "/tmp/file.md.txt.bak")))
    }

    func testCancelledOpenOrSavePanelChangesNothing() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake()
        let bookmarks = OperationBookmarkFake()
        let panel = OperationPanelFake(openURLs: [nil], saveURLs: [nil])
        let document = makeEditedDocument(text: "unchanged")
        let model = makeModel(
            document: document,
            repository: repository,
            bookmarks: bookmarks,
            files: files,
            panel: panel
        )
        let before = document.snapshot()

        await model.requestOpen()
        let saved = await model.saveAs()
        XCTAssertFalse(saved)

        XCTAssertTrue(model.document === document)
        assertSnapshotsEqual(document.snapshot(), before)
        XCTAssertEqual(model.operationState, .idle)
        let storeSelectionCount = await bookmarks.storeSelectionCount
        let openCallCount = await files.openCallCount
        let saveAsReferences = await files.saveAsReferences
        let recoveryWrites = await repository.recoveryWrites
        let deletedDocumentIDs = await repository.deletedDocumentIDs
        XCTAssertEqual(storeSelectionCount, 0)
        XCTAssertEqual(openCallCount, 0)
        XCTAssertEqual(saveAsReferences, [])
        XCTAssertEqual(recoveryWrites, [])
        XCTAssertEqual(deletedDocumentIDs, [])
    }

    func testGenerationChangeDuringDiscardReplacementPreservesLatestRecoveryAndAborts() async {
        let repository = OperationRepositoryFake(deleteSuspended: true)
        let document = makeEditedDocument(text: "approved generation")
        let model = makeModel(
            document: document,
            repository: repository,
            files: ControllableFileServiceFake()
        )

        let replacement = Task { await model.requestNewDocument() }
        guard await waitUntil({ model.pendingDecision != nil }) else {
            replacement.cancel()
            return
        }
        model.resolvePendingDecision(with: .discard)
        await repository.waitForDeleteCalls(1)

        document.storage.setAttributedString(NSAttributedString(string: "newer unapproved text"))
        document.noteUserEdit()
        model.handleCurrentDocumentEdit(document)
        await repository.resumeDelete()
        await replacement.value

        let recoveryWrites = await repository.recoveryWrites
        XCTAssertTrue(model.document === document)
        XCTAssertEqual(document.storage.string, "newer unapproved text")
        XCTAssertEqual(recoveryWrites.last?.unsavedText, "newer unapproved text")
        XCTAssertEqual(model.operationState, .idle)

        let closeRepository = OperationRepositoryFake(deleteSuspended: true)
        let closeDocument = makeEditedDocument(text: "approved discard generation")
        let closeModel = makeModel(
            document: closeDocument,
            repository: closeRepository,
            files: ControllableFileServiceFake()
        )
        let close = Task { await closeModel.requestClose() }
        guard await waitUntil({ closeModel.pendingDecision != nil }) else {
            close.cancel()
            return
        }
        closeModel.resolvePendingDecision(with: .discard)
        await closeRepository.waitForDeleteCalls(1)

        closeDocument.storage.setAttributedString(
            NSAttributedString(string: "newer text during discard deletion")
        )
        closeDocument.noteUserEdit()
        closeModel.handleCurrentDocumentEdit(closeDocument)
        await closeRepository.resumeDelete()
        let closeResult = await close.value

        let closeRecoveryWrites = await closeRepository.recoveryWrites
        XCTAssertFalse(closeResult)
        XCTAssertEqual(closeDocument.storage.string, "newer text during discard deletion")
        XCTAssertEqual(
            closeRecoveryWrites.last?.unsavedText,
            "newer text during discard deletion"
        )
    }

    func testGenerationChangeDuringExitSessionFlushPreservesLatestRecoveryAndAborts() async {
        for startsDirty in [false, true] {
            let repository = OperationRepositoryFake(sessionWriteSuspended: true)
            let document = startsDirty
                ? makeEditedDocument(text: "approved exit generation")
                : makeCleanDocument(text: "clean exit generation")
            let model = makeModel(
                document: document,
                repository: repository,
                files: ControllableFileServiceFake()
            )

            let close = Task { await model.requestClose() }
            if startsDirty {
                guard await waitUntil({ model.pendingDecision != nil }) else {
                    close.cancel()
                    return
                }
                model.resolvePendingDecision(with: .discard)
            }
            await repository.waitForSessionWrites(1)

            document.storage.setAttributedString(NSAttributedString(string: "edit during session write"))
            document.noteUserEdit()
            model.handleCurrentDocumentEdit(document)
            await repository.resumeSessionWrite()
            let closeResult = await close.value

            let recoveryWrites = await repository.recoveryWrites
            let sessionWrites = await repository.sessionWrites
            XCTAssertFalse(closeResult)
            XCTAssertEqual(document.storage.string, "edit during session write")
            XCTAssertEqual(recoveryWrites.last?.unsavedText, "edit during session write")
            XCTAssertEqual(sessionWrites.last?.hasUnsavedChanges, true)
            XCTAssertEqual(sessionWrites.last?.didCloseCleanly, false)
        }
    }

    func testGenerationChangeDuringReloadPreservesLatestRecoveryAndAborts() async {
        let repository = OperationRepositoryFake()
        let files = ControllableFileServiceFake(
            openSuspended: true,
            saveError: .conflict(
                contentHash: "changed-disk-hash",
                modificationDate: Date(timeIntervalSince1970: 50)
            )
        )
        let document = makeEditedDocument(text: "conflicted generation")
        let model = makeModel(document: document, repository: repository, files: files)

        let save = Task { await model.save() }
        guard await waitUntil({
            if case .resolveConflict = model.pendingDecision { return true }
            return false
        }) else {
            save.cancel()
            return
        }
        model.resolvePendingDecision(with: .reloadFromDisk)
        await files.waitForOpenCalls(1)

        document.storage.setAttributedString(NSAttributedString(string: "edit during reload"))
        document.noteUserEdit()
        model.handleCurrentDocumentEdit(document)
        await files.resumeOpenSuccessfully()
        let saveResult = await save.value

        let recoveryWrites = await repository.recoveryWrites
        XCTAssertFalse(saveResult)
        XCTAssertEqual(document.storage.string, "edit during reload")
        XCTAssertTrue(document.hasUnsavedChanges)
        XCTAssertEqual(recoveryWrites.last?.unsavedText, "edit during reload")
    }

    private func makeModel(
        document: DocumentSession,
        launchState: LaunchState = .ready,
        repository: OperationRepositoryFake,
        bookmarks: OperationBookmarkFake = OperationBookmarkFake(),
        files: ControllableFileServiceFake,
        panel: OperationPanelFake = OperationPanelFake(),
        recoveryClock: any RecoveryClock = ImmediateRecoveryClock()
    ) -> ApplicationModel {
        ApplicationModel(
            document: document,
            launchState: launchState,
            servicesFactory: {
                ApplicationServices(
                    repository: repository,
                    bookmarks: bookmarks,
                    files: files,
                    recoveryClock: recoveryClock
                )
            },
            panelProvider: panel,
            windowFrameProvider: { self.frame }
        )
    }

    private func makeEditedDocument(text: String) -> DocumentSession {
        DocumentSession(
            text: text,
            fileReference: ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/tmp/original.md"
            ),
            displayName: "original.md",
            saveState: .edited,
            hasUnsavedChanges: true,
            generation: 4,
            lastSavedHash: "base-hash",
            lastKnownDiskMTime: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeCleanDocument(text: String) -> DocumentSession {
        DocumentSession(
            text: text,
            fileReference: ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/tmp/original.md"
            ),
            displayName: "original.md",
            saveState: .clean,
            hasUnsavedChanges: false,
            generation: 4,
            lastSavedHash: "base-hash",
            lastKnownDiskMTime: Date(timeIntervalSince1970: 10)
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        XCTFail("Timed out waiting for deterministic decision condition")
        return false
    }

    private func waitUntilOrTimeout(
        _ condition: @escaping @MainActor () -> Bool,
        attempts: Int = 1_000
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    private func assertSnapshotsEqual(
        _ lhs: DocumentSnapshot,
        _ rhs: DocumentSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.documentID, rhs.documentID, file: file, line: line)
        XCTAssertEqual(lhs.generation, rhs.generation, file: file, line: line)
        XCTAssertEqual(lhs.text, rhs.text, file: file, line: line)
        XCTAssertEqual(lhs.fileReference, rhs.fileReference, file: file, line: line)
        XCTAssertEqual(lhs.saveState, rhs.saveState, file: file, line: line)
        XCTAssertEqual(lhs.hasUnsavedChanges, rhs.hasUnsavedChanges, file: file, line: line)
        XCTAssertEqual(lhs.selection, rhs.selection, file: file, line: line)
        XCTAssertEqual(lhs.scrollOffsetY, rhs.scrollOffsetY, file: file, line: line)
        XCTAssertEqual(lhs.lineEnding, rhs.lineEnding, file: file, line: line)
        XCTAssertEqual(lhs.lastSavedHash, rhs.lastSavedHash, file: file, line: line)
        XCTAssertEqual(lhs.lastKnownDiskMTime, rhs.lastKnownDiskMTime, file: file, line: line)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.withLock { storage } }
    func increment() { lock.withLock { storage += 1 } }
}

private actor OperationEventRecorder {
    private(set) var events: [String] = []
    func append(_ event: String) { events.append(event) }
}

private actor OperationRepositoryFake: SessionPersisting {
    private let events: OperationEventRecorder?
    private(set) var recoveryWrites: [RecoveryRecord] = []
    private(set) var sessionWrites: [SessionRecord] = []
    private(set) var deletedDocumentIDs: [UUID] = []
    private var recoveryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var sessionWriteWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var deleteWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var remainingDeleteFailures: Int
    private var sessionWriteSuspended: Bool
    private var deleteSuspended: Bool
    private var sessionWriteContinuation: CheckedContinuation<Void, Never>?
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private(set) var deleteCallCount = 0

    init(
        events: OperationEventRecorder? = nil,
        deleteFailures: Int = 0,
        sessionWriteSuspended: Bool = false,
        deleteSuspended: Bool = false
    ) {
        self.events = events
        self.remainingDeleteFailures = deleteFailures
        self.sessionWriteSuspended = sessionWriteSuspended
        self.deleteSuspended = deleteSuspended
    }

    var sessionWriteCount: Int { sessionWrites.count }

    func loadSession() async throws -> SessionRecord? { nil }
    func writeSession(_ record: SessionRecord) async throws {
        sessionWrites.append(record)
        let ready = sessionWriteWaiters.filter { sessionWrites.count >= $0.0 }
        sessionWriteWaiters.removeAll { sessionWrites.count >= $0.0 }
        for waiter in ready { waiter.1.resume() }
        if sessionWriteSuspended {
            sessionWriteSuspended = false
            await withCheckedContinuation { sessionWriteContinuation = $0 }
        }
    }
    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }
    func writeRecovery(_ record: RecoveryRecord) async throws {
        recoveryWrites.append(record)
        let ready = recoveryWaiters.filter { recoveryWrites.count >= $0.0 }
        recoveryWaiters.removeAll { recoveryWrites.count >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
    func deleteRecovery(documentID: UUID) async throws {
        deleteCallCount += 1
        let ready = deleteWaiters.filter { deleteCallCount >= $0.0 }
        deleteWaiters.removeAll { deleteCallCount >= $0.0 }
        for waiter in ready { waiter.1.resume() }
        if deleteSuspended {
            deleteSuspended = false
            await withCheckedContinuation { deleteContinuation = $0 }
        }
        if remainingDeleteFailures > 0 {
            remainingDeleteFailures -= 1
            throw OperationFakeError.deleteFailed
        }
        deletedDocumentIDs.append(documentID)
        await events?.append("delete:\(documentID)")
    }
    func waitForRecoveryWrites(_ count: Int) async {
        guard recoveryWrites.count < count else { return }
        await withCheckedContinuation { recoveryWaiters.append((count, $0)) }
    }

    func waitForSessionWrites(_ count: Int) async {
        guard sessionWrites.count < count else { return }
        await withCheckedContinuation { sessionWriteWaiters.append((count, $0)) }
    }

    func waitForDeleteCalls(_ count: Int) async {
        guard deleteCallCount < count else { return }
        await withCheckedContinuation { deleteWaiters.append((count, $0)) }
    }

    func resumeSessionWrite() {
        sessionWriteContinuation?.resume()
        sessionWriteContinuation = nil
    }

    func resumeDelete() {
        deleteContinuation?.resume()
        deleteContinuation = nil
    }
}

private actor OperationBookmarkFake: BookmarkAccessing {
    private var references: [String: ExternalFileReference] = [:]
    private(set) var storeSelectionCount = 0
    private var storeSelectionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func storeSelection(_ url: URL) async throws -> ExternalFileReference {
        storeSelectionCount += 1
        let ready = storeSelectionWaiters.filter { storeSelectionCount >= $0.0 }
        storeSelectionWaiters.removeAll { storeSelectionCount >= $0.0 }
        for waiter in ready { waiter.1.resume() }
        let path = url.standardizedFileURL.path
        if let reference = references[path] { return reference }
        let reference = ExternalFileReference(bookmarkID: UUID(), pathHint: path)
        references[path] = reference
        return reference
    }
    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference? {
        references.values.first { $0.bookmarkID == bookmarkID }
    }
    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken {
        ScopedAccessToken(id: UUID(), url: URL(fileURLWithPath: reference.pathHint))
    }
    func endAccess(_ token: ScopedAccessToken) async {}
    func refresh(_ token: ScopedAccessToken) async throws {}
    func forget(_ reference: ExternalFileReference) async throws {}

    func waitForStoreSelections(_ count: Int) async {
        guard storeSelectionCount < count else { return }
        await withCheckedContinuation { storeSelectionWaiters.append((count, $0)) }
    }
}

@MainActor
private final class OperationPanelFake: FilePanelProviding {
    private var openURLs: [URL?]
    private var saveURLs: [URL?]

    init(openURLs: [URL?] = [], saveURLs: [URL?] = []) {
        self.openURLs = openURLs
        self.saveURLs = saveURLs
    }

    func selectFileToOpen() async -> URL? {
        openURLs.isEmpty ? nil : openURLs.removeFirst()
    }

    func selectSaveDestination(suggestedName: String) async -> URL? {
        saveURLs.isEmpty ? nil : saveURLs.removeFirst()
    }
}

private actor ControllableFileServiceFake: FileServicing {
    private let events: OperationEventRecorder?
    private let saveError: FileServiceError?
    private let openError: FileServiceError?
    private var saveSuspended: Bool
    private var openSuspended: Bool
    private var saveContinuations: [CheckedContinuation<Result<Void, FileServiceError>, Never>] = []
    private var openContinuations: [CheckedContinuation<Void, Never>] = []
    private var saveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var openWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var lastSaveSnapshot: DocumentSnapshot?
    private(set) var openCallCount = 0
    private(set) var saveCallCount = 0
    private(set) var saveAsReferences: [ExternalFileReference?] = []

    init(
        events: OperationEventRecorder? = nil,
        saveSuspended: Bool = false,
        openSuspended: Bool = false,
        saveError: FileServiceError? = nil,
        openError: FileServiceError? = nil
    ) {
        self.events = events
        self.saveSuspended = saveSuspended
        self.openSuspended = openSuspended
        self.saveError = saveError
        self.openError = openError
    }

    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        openCallCount += 1
        await events?.append("open")
        resumeOpenWaiters()
        if openSuspended {
            openSuspended = false
            await withCheckedContinuation { openContinuations.append($0) }
        }
        if let openError { throw openError }
        return FileOpenResult(
            reference: reference,
            text: "opened text",
            displayName: URL(fileURLWithPath: reference.pathHint).lastPathComponent,
            lineEnding: .lf,
            contentHash: "opened-hash",
            modificationDate: Date(timeIntervalSince1970: 20)
        )
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        saveCallCount += 1
        lastSaveSnapshot = snapshot
        resumeSaveWaiters()
        if saveSuspended {
            saveSuspended = false
            let result = await withCheckedContinuation { saveContinuations.append($0) }
            try result.get()
        }
        if let saveError { throw saveError }
        return makeSaveResult(snapshot, reference: snapshot.fileReference)
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        saveAsReferences.append(reference)
        return makeSaveResult(snapshot, reference: reference)
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus { .unchanged }

    func waitForSaveCalls(_ count: Int) async {
        guard saveCallCount < count else { return }
        await withCheckedContinuation { saveWaiters.append((count, $0)) }
    }

    func waitForOpenCalls(_ count: Int) async {
        guard openCallCount < count else { return }
        await withCheckedContinuation { openWaiters.append((count, $0)) }
    }

    func resumeSaveSuccessfully() {
        resumeSave(with: .success(()))
    }

    func resumeSave(throwing error: FileServiceError) {
        resumeSave(with: .failure(error))
    }

    func resumeOpenSuccessfully() {
        guard !openContinuations.isEmpty else { return }
        openContinuations.removeFirst().resume()
    }

    private func resumeSave(with result: Result<Void, FileServiceError>) {
        guard !saveContinuations.isEmpty else { return }
        saveContinuations.removeFirst().resume(returning: result)
    }

    private func makeSaveResult(
        _ snapshot: DocumentSnapshot,
        reference: ExternalFileReference?
    ) -> FileSaveResult {
        FileSaveResult(
            documentID: snapshot.documentID,
            initiatingGeneration: snapshot.generation,
            reference: reference ?? ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/tmp/saved.md"
            ),
            displayName: URL(fileURLWithPath: reference?.pathHint ?? "/tmp/saved.md").lastPathComponent,
            lineEnding: snapshot.lineEnding,
            contentHash: "verified-hash",
            modificationDate: Date(timeIntervalSince1970: 30)
        )
    }

    private func resumeSaveWaiters() {
        let ready = saveWaiters.filter { saveCallCount >= $0.0 }
        saveWaiters.removeAll { saveCallCount >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }

    private func resumeOpenWaiters() {
        let ready = openWaiters.filter { openCallCount >= $0.0 }
        openWaiters.removeAll { openCallCount >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
}

private struct ImmediateRecoveryClock: RecoveryClock {
    func sleep(for duration: Duration) async throws {}
}

private actor SuspendingRecoveryClock: RecoveryClock {
    private var entries = 0
    private var entryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var sleepers: [UUID: CheckedContinuation<Void, Error>] = [:]

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        entries += 1
        let ready = entryWaiters.filter { entries >= $0.0 }
        entryWaiters.removeAll { entries >= $0.0 }
        for waiter in ready { waiter.1.resume() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { sleepers[id] = $0 }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func waitForSleepEntries(_ count: Int) async {
        guard entries < count else { return }
        await withCheckedContinuation { entryWaiters.append((count, $0)) }
    }

    private func cancel(id: UUID) {
        sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

private enum OperationFakeError: Error {
    case deleteFailed
}
