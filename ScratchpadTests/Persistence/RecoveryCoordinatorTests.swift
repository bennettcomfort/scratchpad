import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class RecoveryCoordinatorTests: XCTestCase {
    func testDebounceTasksAreIndependentByDocumentID() async throws {
        let repository = RecoveryRepositorySpy()
        let clock = VirtualRecoveryClock()
        let first = DocumentSession(text: "first", hasUnsavedChanges: true, generation: 1)
        let second = DocumentSession(text: "second", hasUnsavedChanges: true, generation: 1)
        let documents = DocumentLookup([first, second])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: first)
        coordinator.scheduleRecovery(for: second)
        await clock.waitForSleepers(2)
        await clock.advance(by: .seconds(2))
        await waitForRecoveryWrites(2, repository: repository)

        let records = await repository.recoveryWrites
        XCTAssertEqual(Set(records.map(\.documentID)), Set([first.id, second.id]))
        XCTAssertEqual(Set(records.map(\.unsavedText)), Set(["first", "second"]))
    }

    func testRepeatedEditWritesOnlyFreshestSnapshotAfterTwoSeconds() async throws {
        let repository = RecoveryRepositorySpy()
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(text: "generation 1", hasUnsavedChanges: true, generation: 1)
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        await clock.waitForSleepers(1)
        document.storage.setAttributedString(NSAttributedString(string: "generation 2"))
        document.noteUserEdit()
        await clock.advance(by: .seconds(2))
        await waitForRecoveryWrites(1, repository: repository)

        let records = await repository.recoveryWrites
        XCTAssertEqual(records.map(\.unsavedText), ["generation 2"])
        XCTAssertEqual(document.generation, 2)
    }

    func testMetadataUpdatesPreservePendingTextRecoveryDeadline() async throws {
        let repository = RecoveryRepositorySpy()
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(
            text: "dirty text",
            hasUnsavedChanges: true,
            generation: 1
        )
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        guard await waitForSleeperCount(1, clock: clock) else { return }
        await clock.advance(by: .seconds(1))

        document.updateSelection(TextSelection(location: 2, length: 3))
        coordinator.ensureRecoveryScheduled(for: document)
        document.updateScrollOffset(47)
        coordinator.ensureRecoveryScheduled(for: document)

        let deadlines = await clock.activeDeadlines
        guard deadlines == [.seconds(2)] else {
            XCTFail("Metadata restarted the pending text recovery deadline: \(deadlines)")
            await clock.advance(by: .seconds(2))
            return
        }
        await clock.advance(by: .seconds(1))
        await waitForRecoveryWrites(1, repository: repository)

        let records = await repository.recoveryWrites
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.unsavedText, "dirty text")
        XCTAssertEqual(records.first?.selection, TextSelection(location: 2, length: 3))
        XCTAssertEqual(records.first?.scrollOffsetY, 47)
    }

    func testMetadataAfterCompletedRecoverySchedulesFreshSnapshot() async throws {
        let repository = RecoveryRepositorySpy()
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(
            text: "dirty text",
            hasUnsavedChanges: true,
            generation: 1
        )
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        guard await waitForSleeperCount(1, clock: clock) else { return }
        await clock.advance(by: .seconds(2))
        await waitForRecoveryWrites(1, repository: repository)
        for _ in 0..<10 { await Task.yield() }

        document.updateSelection(TextSelection(location: 4, length: 2))
        document.updateScrollOffset(83)
        coordinator.ensureRecoveryScheduled(for: document)
        guard await waitForSleeperCount(1, clock: clock) else { return }
        await clock.advance(by: .seconds(2))
        await waitForRecoveryWrites(2, repository: repository)

        let records = await repository.recoveryWrites
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.selection, TextSelection(location: 4, length: 2))
        XCTAssertEqual(records.last?.scrollOffsetY, 83)
    }

    func testMetadataDuringSuspendedWriteSchedulesExactlyOneFreshFollowUp() async throws {
        let repository = RecoveryRepositorySpy(suspendedRecoveryWriteCount: 1)
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(
            text: "dirty text",
            hasUnsavedChanges: true,
            generation: 1
        )
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        guard await waitForSleeperCount(1, clock: clock) else { return }
        await clock.advance(by: .seconds(2))
        await repository.waitForRecoveryWriteEntries(1)

        document.updateSelection(TextSelection(location: 2, length: 1))
        coordinator.ensureRecoveryScheduled(for: document)
        document.updateSelection(TextSelection(location: 6, length: 2))
        document.updateScrollOffset(119)
        coordinator.ensureRecoveryScheduled(for: document)
        coordinator.ensureRecoveryScheduled(for: document)

        await repository.releaseNextRecoveryWrite()
        await waitForRecoveryWrites(1, repository: repository)
        guard await waitForSleeperCount(1, clock: clock) else { return }
        await clock.advance(by: .seconds(2))
        await waitForRecoveryWrites(2, repository: repository)

        let records = await repository.recoveryWrites
        let finalRecord = await repository.storedRecovery(documentID: document.id)
        let remainingSleeperCount = await clock.activeSleeperCount
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.selection, TextSelection(location: 0, length: 0))
        XCTAssertEqual(records.first?.scrollOffsetY, 0)
        XCTAssertEqual(records.last?.selection, TextSelection(location: 6, length: 2))
        XCTAssertEqual(records.last?.scrollOffsetY, 119)
        XCTAssertEqual(finalRecord, records.last)
        XCTAssertEqual(remainingSleeperCount, 0)
    }

    func testExplicitFlushClearsMetadataFollowUpAndFinishesNewest() async throws {
        let repository = RecoveryRepositorySpy(suspendedRecoveryWriteCount: 1)
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(
            text: "dirty text",
            hasUnsavedChanges: true,
            generation: 1
        )
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        guard await waitForSleeperCount(1, clock: clock) else { return }
        await clock.advance(by: .seconds(2))
        await repository.waitForRecoveryWriteEntries(1)

        document.updateSelection(TextSelection(location: 4, length: 3))
        document.updateScrollOffset(71)
        coordinator.ensureRecoveryScheduled(for: document)
        let flush = Task { try await coordinator.flushRecovery(for: document) }
        await repository.releaseNextRecoveryWrite()
        try await flush.value

        let records = await repository.recoveryWrites
        let finalRecord = await repository.storedRecovery(documentID: document.id)
        let remainingSleeperCount = await clock.activeSleeperCount
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.selection, TextSelection(location: 4, length: 3))
        XCTAssertEqual(records.last?.scrollOffsetY, 71)
        XCTAssertEqual(finalRecord, records.last)
        XCTAssertEqual(remainingSleeperCount, 0)
    }

    func testExplicitFlushCancelsPendingTaskAndWritesLatestText() async throws {
        let repository = RecoveryRepositorySpy()
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(text: "old", hasUnsavedChanges: true, generation: 1)
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        await clock.waitForSleepers(1)
        document.storage.setAttributedString(NSAttributedString(string: "latest"))
        document.noteUserEdit()
        try await coordinator.flushRecovery(for: document)
        await clock.advance(by: .seconds(2))
        await Task.yield()

        let records = await repository.recoveryWrites
        XCTAssertEqual(records.map(\.unsavedText), ["latest"])
    }

    func testRescheduledDebounceWaitsForInFlightWriteAndPersistsNewestGeneration() async throws {
        let repository = RecoveryRepositorySpy(suspendedRecoveryWriteCount: 1)
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(text: "old", hasUnsavedChanges: true, generation: 1)
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(2))
        await repository.waitForRecoveryWriteEntries(1)

        document.storage.setAttributedString(NSAttributedString(string: "new"))
        document.noteUserEdit()
        coordinator.scheduleRecovery(for: document)
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(2))
        await repository.releaseNextRecoveryWrite()
        await waitForRecoveryWrites(2, repository: repository)

        let records = await repository.recoveryWrites
        let finalRecord = await repository.storedRecovery(documentID: document.id)
        XCTAssertEqual(records.map(\.unsavedText), ["old", "new"])
        XCTAssertEqual(finalRecord?.unsavedText, "new")
    }

    func testExplicitFlushWaitsForInFlightWriteAndFinishesNewest() async throws {
        let repository = RecoveryRepositorySpy(suspendedRecoveryWriteCount: 1)
        let clock = VirtualRecoveryClock()
        let document = DocumentSession(text: "old", hasUnsavedChanges: true, generation: 1)
        let documents = DocumentLookup([document])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )

        coordinator.scheduleRecovery(for: document)
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(2))
        await repository.waitForRecoveryWriteEntries(1)

        document.storage.setAttributedString(NSAttributedString(string: "flushed"))
        document.noteUserEdit()
        let flush = Task { try await coordinator.flushRecovery(for: document) }
        await Task.yield()
        await repository.releaseNextRecoveryWrite()
        try await flush.value

        let records = await repository.recoveryWrites
        let finalRecord = await repository.storedRecovery(documentID: document.id)
        XCTAssertEqual(records.map(\.unsavedText), ["old", "flushed"])
        XCTAssertEqual(finalRecord?.unsavedText, "flushed")
    }

    func testSessionFlushRecordsSelectionScrollAndCleanFlag() async throws {
        let repository = RecoveryRepositorySpy()
        let documentID = UUID()
        let document = DocumentSession(
            id: documentID,
            text: "session text",
            displayName: "Session",
            saveState: .edited,
            hasUnsavedChanges: true,
            selection: TextSelection(location: 3, length: 4),
            scrollOffsetY: 27
        )
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { _ in nil }
        )
        let frame = CGRect(x: 10, y: 20, width: 820, height: 640)

        try await coordinator.flushSession(
            for: document,
            windowFrame: frame,
            didCloseCleanly: false
        )

        let records = await repository.sessionWrites
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.documentID, documentID)
        XCTAssertEqual(record.selection, TextSelection(location: 3, length: 4))
        XCTAssertEqual(record.scrollOffsetY, 27)
        XCTAssertEqual(record.windowFrame, frame)
        XCTAssertFalse(record.didCloseCleanly)
    }

    func testUnsavedOrNonemptyUntitledLaunchPrefersRecoveryText() async throws {
        let documentID = UUID()
        let sessionBookmarkID = UUID()
        let recoveryBookmarkID = UUID()
        let sessionReference = ExternalFileReference(
            bookmarkID: sessionBookmarkID,
            pathHint: "/Notes/Old.md"
        )
        let recoveryReference = ExternalFileReference(
            bookmarkID: recoveryBookmarkID,
            pathHint: "/Notes/Dirty.md"
        )
        let session = makeSession(
            documentID: documentID,
            fileReferenceID: sessionBookmarkID,
            hasUnsavedChanges: true,
            saveState: .edited
        )
        let recovery = makeRecovery(
            documentID: documentID,
            fileReferenceID: recoveryBookmarkID,
            filePathHint: recoveryReference.pathHint,
            text: "recovered text"
        )
        let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        let source = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(
                references: [
                    sessionBookmarkID: sessionReference,
                    recoveryBookmarkID: recoveryReference,
                ]
            ),
            files: LaunchFileServiceSpy(),
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(source, .recovery(recovery))
        XCTAssertEqual(model.document.id, documentID)
        XCTAssertEqual(model.document.storage.string, "recovered text")
        XCTAssertEqual(model.document.fileReference, recoveryReference)
        XCTAssertTrue(model.document.hasUnsavedChanges)
        XCTAssertEqual(model.document.selection, recovery.selection)
        XCTAssertEqual(model.document.scrollOffsetY, recovery.scrollOffsetY)
        let launchSessionWrites = await repository.sessionWrites
        let launchSession = try XCTUnwrap(launchSessionWrites.last)
        XCTAssertFalse(launchSession.didCloseCleanly)

        let nonemptyUntitledSession = makeSession(
            documentID: documentID,
            hasUnsavedChanges: false,
            saveState: .untitled
        )
        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: nonemptyUntitledSession,
                recovery: recovery,
                fileReference: nil
            ),
            .recovery(recovery)
        )

        let untitledRecovery = makeRecovery(
            documentID: documentID,
            text: "nonempty untitled"
        )
        let untitledRepository = RecoveryRepositorySpy(
            session: nonemptyUntitledSession,
            recoveries: [untitledRecovery]
        )
        let untitledModel = ApplicationModel()
        let untitledCoordinator = RecoveryCoordinator(
            repository: untitledRepository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in
                untitledModel.document.id == id ? untitledModel.document : nil
            }
        )
        _ = try await untitledModel.restoreAtLaunch(
            repository: untitledRepository,
            bookmarks: BookmarkAccessSpy(),
            files: LaunchFileServiceSpy(),
            recoveryCoordinator: untitledCoordinator,
            windowFrame: nonemptyUntitledSession.windowFrame
        )
        XCTAssertTrue(untitledModel.document.hasUnsavedChanges)
        XCTAssertEqual(untitledModel.document.saveState, .edited)
    }

    func testCleanFileBackedLaunchReopensDiskInsteadOfRecoveryText() async throws {
        let documentID = UUID()
        let bookmarkID = UUID()
        let reference = ExternalFileReference(bookmarkID: bookmarkID, pathHint: "/Notes/File.md")
        let session = makeSession(
            documentID: documentID,
            documentGeneration: 2,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean
        )
        let recovery = makeRecovery(
            documentID: documentID,
            documentGeneration: 1,
            text: "stale recovery",
            savedAt: Date(timeIntervalSince1970: 20)
        )
        let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
        let bookmarks = BookmarkAccessSpy(references: [bookmarkID: reference])
        let files = LaunchFileServiceSpy(
            openResult: FileOpenResult(
                reference: reference,
                text: "current disk text",
                displayName: "File.md",
                lineEnding: .lf,
                contentHash: "disk-hash",
                modificationDate: Date(timeIntervalSince1970: 50)
            )
        )
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        let source = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: bookmarks,
            files: files,
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(source, .file(session, reference))
        XCTAssertEqual(model.document.storage.string, "current disk text")
        XCTAssertEqual(model.document.generation, 2)
        XCTAssertEqual(model.document.selection, session.selection)
        XCTAssertEqual(model.document.scrollOffsetY, session.scrollOffsetY)
        let openedReferences = await files.openedReferences
        XCTAssertEqual(openedReferences, [reference])
    }

    func testNewerMatchingRecoveryOverridesStaleCleanFileSession() async throws {
        let documentID = UUID()
        let staleSessionBookmarkID = UUID()
        let recoveryBookmarkID = UUID()
        let reference = ExternalFileReference(
            bookmarkID: recoveryBookmarkID,
            pathHint: "/Notes/Edited.md"
        )
        let cleanSession = makeSession(
            documentID: documentID,
            documentGeneration: 1,
            fileReferenceID: staleSessionBookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean
        )
        let editedDocument = DocumentSession(
            id: documentID,
            text: "original disk text",
            fileReference: reference,
            displayName: "Edited.md",
            saveState: .clean,
            hasUnsavedChanges: false,
            generation: 1,
            lastSavedHash: "base-hash",
            lastKnownDiskMTime: Date(timeIntervalSince1970: 40)
        )
        editedDocument.storage.setAttributedString(
            NSAttributedString(string: "unsaved text after replacement")
        )
        editedDocument.noteUserEdit()

        let repository = RecoveryRepositorySpy(session: cleanSession)
        let clock = VirtualRecoveryClock()
        let documents = DocumentLookup([editedDocument])
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { documents.document(id: $0) }
        )
        coordinator.scheduleRecovery(for: editedDocument)
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(2))
        await waitForRecoveryWrites(1, repository: repository)

        let launchModel = ApplicationModel()
        let launchCoordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in
                launchModel.document.id == id ? launchModel.document : nil
            }
        )
        let source = try await launchModel.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(references: [recoveryBookmarkID: reference]),
            files: LaunchFileServiceSpy(
                openResult: FileOpenResult(
                    reference: reference,
                    text: "original disk text",
                    displayName: "Edited.md",
                    lineEnding: .lf,
                    contentHash: "base-hash",
                    modificationDate: Date(timeIntervalSince1970: 40)
                )
            ),
            recoveryCoordinator: launchCoordinator,
            windowFrame: cleanSession.windowFrame
        )

        let storedRecovery = await repository.storedRecovery(documentID: documentID)
        let recovery = try XCTUnwrap(storedRecovery)
        XCTAssertEqual(source, .recovery(recovery))
        XCTAssertEqual(launchModel.document.storage.string, "unsaved text after replacement")
        XCTAssertTrue(launchModel.document.hasUnsavedChanges)
        XCTAssertEqual(launchModel.document.saveState, .edited)
        XCTAssertEqual(launchModel.document.fileReference, reference)
        XCTAssertEqual(launchModel.document.generation, 2)
    }

    func testGenerationAuthorityIgnoresWallClockRollback() {
        let documentID = UUID()
        let bookmarkID = UUID()
        let reference = ExternalFileReference(
            bookmarkID: bookmarkID,
            pathHint: "/Notes/Clock.md"
        )
        let cleanSession = makeSession(
            documentID: documentID,
            documentGeneration: 4,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean,
            savedAt: Date(timeIntervalSince1970: 100)
        )
        let newerRecoveryWithEarlierClock = makeRecovery(
            documentID: documentID,
            documentGeneration: 5,
            text: "newer generation",
            savedAt: Date(timeIntervalSince1970: 50)
        )
        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: cleanSession,
                recovery: newerRecoveryWithEarlierClock,
                fileReference: reference
            ),
            .recovery(newerRecoveryWithEarlierClock)
        )

        let staleRecoveryWithLaterClock = makeRecovery(
            documentID: documentID,
            documentGeneration: 3,
            text: "stale generation",
            savedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: cleanSession,
                recovery: staleRecoveryWithLaterClock,
                fileReference: reference
            ),
            .file(cleanSession, reference)
        )
    }

    func testRolledOverRecoveryGenerationOverridesCleanTerminalSession() {
        let documentID = UUID()
        let bookmarkID = UUID()
        let reference = ExternalFileReference(
            bookmarkID: bookmarkID,
            pathHint: "/Notes/Rollover.md"
        )
        let session = makeSession(
            documentID: documentID,
            documentGeneration: Int.max,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean
        )
        let recovery = makeRecovery(
            documentID: documentID,
            documentGeneration: 0,
            text: "edit after rollover"
        )

        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: session,
                recovery: recovery,
                fileReference: reference
            ),
            .recovery(recovery)
        )
    }

    func testLegacyCleanSessionUsesMatchingBaseRecoveryWithoutWallClockAuthority() {
        let documentID = UUID()
        let bookmarkID = UUID()
        let reference = ExternalFileReference(
            bookmarkID: bookmarkID,
            pathHint: "/Notes/Legacy.md"
        )
        let cleanSession = makeSession(
            documentID: documentID,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean,
            savedAt: Date(timeIntervalSince1970: 100)
        )
        let matchingBaseRecovery = makeRecovery(
            documentID: documentID,
            fileReferenceID: bookmarkID,
            text: "unsaved legacy edit",
            baseDiskHash: "base-hash",
            savedAt: Date(timeIntervalSince1970: 50)
        )

        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: cleanSession,
                recovery: matchingBaseRecovery,
                fileReference: reference
            ),
            .recovery(matchingBaseRecovery)
        )

        let staleRecovery = makeRecovery(
            documentID: documentID,
            fileReferenceID: bookmarkID,
            text: "stale pre-save text",
            baseDiskHash: "older-disk-hash",
            savedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: cleanSession,
                recovery: staleRecovery,
                fileReference: reference
            ),
            .file(cleanSession, reference)
        )
    }

    func testDirtySessionPreservesMatchingRecoveryWhenRecoveryGenerationIsLower() {
        let documentID = UUID()
        let dirtySession = makeSession(
            documentID: documentID,
            documentGeneration: 8,
            hasUnsavedChanges: true,
            saveState: .edited
        )
        let lastDurableRecovery = makeRecovery(
            documentID: documentID,
            documentGeneration: 7,
            text: "last durable unsaved text"
        )

        XCTAssertEqual(
            RecoveryCoordinator.restoreSource(
                session: dirtySession,
                recovery: lastDurableRecovery,
                fileReference: nil
            ),
            .recovery(lastDurableRecovery)
        )
    }

    func testPendingSaveAsPromotesMatchingDestinationForExistingAndUntitledSources() async throws {
        for startsFileBacked in [true, false] {
            let documentID = UUID()
            let sourceID = UUID()
            let destinationID = UUID()
            let sourceReference = ExternalFileReference(
                bookmarkID: sourceID,
                pathHint: "/Notes/Source.md"
            )
            let destinationReference = ExternalFileReference(
                bookmarkID: destinationID,
                pathHint: "/Notes/Destination.md"
            )
            let session = makeSession(
                documentID: documentID,
                documentGeneration: 4,
                fileReferenceID: startsFileBacked ? sourceID : nil,
                hasUnsavedChanges: true,
                saveState: .edited
            )
            let pending = PendingSaveAsRecord(
                destinationFileReferenceID: destinationID,
                destinationPathHint: destinationReference.pathHint,
                expectedContentHash: "destination-hash"
            )
            let recovery = makeRecovery(
                documentID: documentID,
                documentGeneration: 4,
                fileReferenceID: startsFileBacked ? sourceID : nil,
                filePathHint: startsFileBacked ? sourceReference.pathHint : nil,
                text: "exact pending text",
                baseDiskHash: startsFileBacked ? "base-hash" : nil,
                pendingSaveAs: pending
            )
            let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
            let model = ApplicationModel()
            let coordinator = RecoveryCoordinator(
                repository: repository,
                clock: VirtualRecoveryClock(),
                documentProvider: { id in model.document.id == id ? model.document : nil }
            )
            var references = [destinationID: destinationReference]
            if startsFileBacked { references[sourceID] = sourceReference }

            let source = try await model.restoreAtLaunch(
                repository: repository,
                bookmarks: BookmarkAccessSpy(references: references),
                files: LaunchFileServiceSpy(
                    openResult: FileOpenResult(
                        reference: destinationReference,
                        text: "exact pending text",
                        displayName: "Destination.md",
                        lineEnding: .lf,
                        contentHash: "destination-hash",
                        modificationDate: Date(timeIntervalSince1970: 80)
                    )
                ),
                recoveryCoordinator: coordinator,
                windowFrame: session.windowFrame
            )

            let storedRecovery = await repository.storedRecovery(documentID: documentID)
            let verified = try XCTUnwrap(storedRecovery)
            XCTAssertEqual(source, .recovery(verified))
            XCTAssertNil(verified.pendingSaveAs)
            XCTAssertEqual(verified.fileReferenceID, destinationID)
            XCTAssertEqual(verified.baseDiskHash, "destination-hash")
            XCTAssertEqual(model.document.fileReference, destinationReference)
            XCTAssertTrue(model.document.hasUnsavedChanges)
        }
    }

    func testCleanPendingSaveAsPromotesVerifiedDestinationWithNewLogicalRevision() async throws {
        for startsFileBacked in [true, false] {
            let documentID = UUID()
            let sourceID = UUID()
            let destinationID = UUID()
            let sourceReference = ExternalFileReference(
                bookmarkID: sourceID,
                pathHint: "/Notes/CleanSource.md"
            )
            let destinationReference = ExternalFileReference(
                bookmarkID: destinationID,
                pathHint: "/Notes/CleanDestination.md"
            )
            let session = makeSession(
                documentID: documentID,
                documentGeneration: 4,
                fileReferenceID: startsFileBacked ? sourceID : nil,
                hasUnsavedChanges: false,
                saveState: startsFileBacked ? .clean : .untitled
            )
            let recovery = makeRecovery(
                documentID: documentID,
                documentGeneration: 4,
                fileReferenceID: startsFileBacked ? sourceID : nil,
                filePathHint: startsFileBacked ? sourceReference.pathHint : nil,
                text: startsFileBacked ? "clean saved-as text" : "",
                baseDiskHash: startsFileBacked ? "base-hash" : nil,
                pendingSaveAs: PendingSaveAsRecord(
                    destinationFileReferenceID: destinationID,
                    destinationPathHint: destinationReference.pathHint,
                    expectedContentHash: "verified-destination-hash"
                )
            )
            let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
            let model = ApplicationModel()
            let coordinator = RecoveryCoordinator(
                repository: repository,
                clock: VirtualRecoveryClock(),
                documentProvider: { id in model.document.id == id ? model.document : nil }
            )
            var references = [destinationID: destinationReference]
            if startsFileBacked { references[sourceID] = sourceReference }

            _ = try await model.restoreAtLaunch(
                repository: repository,
                bookmarks: BookmarkAccessSpy(references: references),
                files: LaunchFileServiceSpy(
                    openResult: FileOpenResult(
                        reference: destinationReference,
                        text: recovery.unsavedText,
                        displayName: "CleanDestination.md",
                        lineEnding: .lf,
                        contentHash: "verified-destination-hash",
                        modificationDate: Date(timeIntervalSince1970: 120)
                    )
                ),
                recoveryCoordinator: coordinator,
                windowFrame: session.windowFrame
            )

            let storedRecord = await repository.storedRecovery(documentID: documentID)
            let stored = try XCTUnwrap(storedRecord)
            XCTAssertEqual(stored.documentGeneration, 5)
            XCTAssertNil(stored.pendingSaveAs)
            XCTAssertEqual(stored.fileReferenceID, destinationID)
            XCTAssertEqual(stored.baseDiskHash, "verified-destination-hash")
            XCTAssertEqual(stored.baseDiskMTime, Date(timeIntervalSince1970: 120))
            XCTAssertEqual(model.document.fileReference, destinationReference)
            XCTAssertEqual(model.document.generation, 5)
            XCTAssertTrue(model.document.hasUnsavedChanges)
        }
    }

    func testCleanStalePendingSaveAsNeverPromotesMatchingDestination() async throws {
        for generations in [(session: 5, recovery: 4), (session: 0, recovery: Int.max)] {
            let documentID = UUID()
            let sourceReference = ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/Notes/Current.md"
            )
            let destinationReference = ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/Notes/StaleDestination.md"
            )
            let session = makeSession(
                documentID: documentID,
                documentGeneration: generations.session,
                fileReferenceID: sourceReference.bookmarkID,
                hasUnsavedChanges: false,
                saveState: .clean
            )
            let pendingRecovery = makeRecovery(
                documentID: documentID,
                documentGeneration: generations.recovery,
                fileReferenceID: sourceReference.bookmarkID,
                filePathHint: sourceReference.pathHint,
                text: "stale pending text",
                pendingSaveAs: PendingSaveAsRecord(
                    destinationFileReferenceID: destinationReference.bookmarkID,
                    destinationPathHint: destinationReference.pathHint,
                    expectedContentHash: "matching-old-hash"
                )
            )
            let repository = RecoveryRepositorySpy(
                session: session,
                recoveries: [pendingRecovery]
            )
            let files = LaunchFileServiceSpy(
                openResult: FileOpenResult(
                    reference: sourceReference,
                    text: "current disk text",
                    displayName: "Current.md",
                    lineEnding: .lf,
                    contentHash: "matching-old-hash",
                    modificationDate: Date(timeIntervalSince1970: 140)
                )
            )
            let model = ApplicationModel()
            let coordinator = RecoveryCoordinator(
                repository: repository,
                clock: VirtualRecoveryClock(),
                documentProvider: { id in model.document.id == id ? model.document : nil }
            )

            let source = try await model.restoreAtLaunch(
                repository: repository,
                bookmarks: BookmarkAccessSpy(
                    references: [
                        sourceReference.bookmarkID: sourceReference,
                        destinationReference.bookmarkID: destinationReference,
                    ]
                ),
                files: files,
                recoveryCoordinator: coordinator,
                windowFrame: session.windowFrame
            )

            XCTAssertEqual(source, .file(session, sourceReference))
            XCTAssertEqual(model.document.fileReference, sourceReference)
            XCTAssertEqual(model.document.storage.string, "current disk text")
            let openedReferences = await files.openedReferences
            let storedRecovery = await repository.storedRecovery(documentID: documentID)
            XCTAssertEqual(openedReferences, [sourceReference])
            XCTAssertEqual(
                storedRecovery,
                pendingRecovery
            )
        }
    }

    func testCleanPendingSaveAsWithoutDestinationBytesRemainsNonAuthoritative() async throws {
        for startsFileBacked in [true, false] {
            let documentID = UUID()
            let sourceID = UUID()
            let destinationID = UUID()
            let sourceReference = ExternalFileReference(
                bookmarkID: sourceID,
                pathHint: "/Notes/CleanSource.md"
            )
            let session = makeSession(
                documentID: documentID,
                documentGeneration: 4,
                fileReferenceID: startsFileBacked ? sourceID : nil,
                hasUnsavedChanges: false,
                saveState: startsFileBacked ? .clean : .untitled
            )
            let recovery = makeRecovery(
                documentID: documentID,
                documentGeneration: 4,
                fileReferenceID: startsFileBacked ? sourceID : nil,
                filePathHint: startsFileBacked ? sourceReference.pathHint : nil,
                text: "",
                baseDiskHash: startsFileBacked ? "base-hash" : nil,
                pendingSaveAs: PendingSaveAsRecord(
                    destinationFileReferenceID: destinationID,
                    destinationPathHint: "/Notes/NeverWritten.md",
                    expectedContentHash: "never-written-hash"
                )
            )
            let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
            let model = ApplicationModel()
            let coordinator = RecoveryCoordinator(
                repository: repository,
                clock: VirtualRecoveryClock(),
                documentProvider: { id in model.document.id == id ? model.document : nil }
            )
            let files = LaunchFileServiceSpy(
                openResult: startsFileBacked
                    ? FileOpenResult(
                        reference: sourceReference,
                        text: "clean disk text",
                        displayName: "CleanSource.md",
                        lineEnding: .lf,
                        contentHash: "base-hash",
                        modificationDate: Date(timeIntervalSince1970: 40)
                    )
                    : nil
            )

            let source = try await model.restoreAtLaunch(
                repository: repository,
                bookmarks: BookmarkAccessSpy(
                    references: startsFileBacked ? [sourceID: sourceReference] : [:]
                ),
                files: files,
                recoveryCoordinator: coordinator,
                windowFrame: session.windowFrame
            )

            XCTAssertEqual(
                source,
                startsFileBacked ? .file(session, sourceReference) : .empty
            )
            XCTAssertEqual(model.document.fileReference, startsFileBacked ? sourceReference : nil)
            XCTAssertFalse(model.document.hasUnsavedChanges)
            let stored = await repository.storedRecovery(documentID: documentID)
            XCTAssertEqual(stored, recovery)
        }
    }

    func testPendingSaveAsDifferentDestinationBytesRestorePriorAssociationAndPreserveJournal() async throws {
        let documentID = UUID()
        let sourceID = UUID()
        let destinationID = UUID()
        let sourceReference = ExternalFileReference(
            bookmarkID: sourceID,
            pathHint: "/Notes/Source.md"
        )
        let destinationReference = ExternalFileReference(
            bookmarkID: destinationID,
            pathHint: "/Notes/Occupied.md"
        )
        let session = makeSession(
            documentID: documentID,
            documentGeneration: 4,
            fileReferenceID: sourceID,
            hasUnsavedChanges: true,
            saveState: .edited
        )
        let recovery = makeRecovery(
            documentID: documentID,
            documentGeneration: 4,
            fileReferenceID: sourceID,
            filePathHint: sourceReference.pathHint,
            text: "keep source edit",
            baseDiskHash: "base-hash",
            pendingSaveAs: PendingSaveAsRecord(
                destinationFileReferenceID: destinationID,
                destinationPathHint: destinationReference.pathHint,
                expectedContentHash: "expected-hash"
            )
        )
        let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        let source = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(
                references: [sourceID: sourceReference, destinationID: destinationReference]
            ),
            files: LaunchFileServiceSpy(
                openResult: FileOpenResult(
                    reference: destinationReference,
                    text: "somebody else's bytes",
                    displayName: "Occupied.md",
                    lineEnding: .lf,
                    contentHash: "different-hash",
                    modificationDate: Date(timeIntervalSince1970: 90)
                )
            ),
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(source, .recovery(recovery))
        XCTAssertEqual(model.document.fileReference, sourceReference)
        let storedRecovery = await repository.storedRecovery(documentID: documentID)
        XCTAssertEqual(storedRecovery, recovery)
    }

    func testPendingSaveAsMissingOrDeniedDestinationNeverUsesPathFallback() async throws {
        for mode in 0..<3 {
            let documentID = UUID()
            let destinationID = UUID()
            let destinationReference = ExternalFileReference(
                bookmarkID: destinationID,
                pathHint: "/Notes/UntrustedPath.md"
            )
            let session = makeSession(
                documentID: documentID,
                documentGeneration: 2,
                hasUnsavedChanges: true,
                saveState: .edited
            )
            let recovery = makeRecovery(
                documentID: documentID,
                documentGeneration: 2,
                text: "untitled survives",
                pendingSaveAs: PendingSaveAsRecord(
                    destinationFileReferenceID: destinationID,
                    destinationPathHint: destinationReference.pathHint,
                    expectedContentHash: "expected-hash"
                )
            )
            let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
            let model = ApplicationModel()
            let coordinator = RecoveryCoordinator(
                repository: repository,
                clock: VirtualRecoveryClock(),
                documentProvider: { id in model.document.id == id ? model.document : nil }
            )
            let bookmarks: BookmarkAccessSpy
            let files: LaunchFileServiceSpy
            switch mode {
            case 0:
                bookmarks = BookmarkAccessSpy()
                files = LaunchFileServiceSpy()
            case 1:
                bookmarks = BookmarkAccessSpy(
                    references: [destinationID: destinationReference],
                    deniedReferenceIDs: [destinationID]
                )
                files = LaunchFileServiceSpy()
            default:
                bookmarks = BookmarkAccessSpy(references: [destinationID: destinationReference])
                files = LaunchFileServiceSpy(openError: .missing)
            }

            let source = try await model.restoreAtLaunch(
                repository: repository,
                bookmarks: bookmarks,
                files: files,
                recoveryCoordinator: coordinator,
                windowFrame: session.windowFrame
            )

            XCTAssertEqual(source, .recovery(recovery))
            XCTAssertNil(model.document.fileReference)
            let storedRecovery = await repository.storedRecovery(documentID: documentID)
            XCTAssertEqual(storedRecovery, recovery)
            let openedReferences = await files.openedReferences
            XCTAssertEqual(openedReferences, mode == 2 ? [destinationReference] : [])
        }
    }

    func testUnreadableSessionPreservesOrphanRecoveryForNextLaunch() async throws {
        let orphan = makeRecovery(documentID: UUID(), text: "do not delete")
        let repository = RecoveryRepositorySpy(session: nil, recoveries: [orphan])
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        let source = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(),
            files: LaunchFileServiceSpy(),
            recoveryCoordinator: coordinator,
            windowFrame: .zero
        )

        XCTAssertEqual(source, .empty)
        XCTAssertEqual(model.document.storage.string, "")
        let deletedRecoveryIDs = await repository.deletedRecoveryIDs
        let storedRecoveries = await repository.storedRecoveries
        XCTAssertEqual(deletedRecoveryIDs, [])
        XCTAssertEqual(storedRecoveries, [orphan])
    }

    func testRecoveryUsesRecoveryBookmarkWhenSessionBookmarkDiffers() async throws {
        let documentID = UUID()
        let sessionBookmarkID = UUID()
        let recoveryBookmarkID = UUID()
        let sessionReference = ExternalFileReference(
            bookmarkID: sessionBookmarkID,
            pathHint: "/Notes/Session.md"
        )
        let recoveryReference = ExternalFileReference(
            bookmarkID: recoveryBookmarkID,
            pathHint: "/Notes/Recovery.md"
        )
        let session = makeSession(
            documentID: documentID,
            fileReferenceID: sessionBookmarkID,
            hasUnsavedChanges: true,
            saveState: .edited
        )
        let recovery = makeRecovery(
            documentID: documentID,
            fileReferenceID: recoveryBookmarkID,
            filePathHint: recoveryReference.pathHint,
            text: "recovered"
        )
        let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        _ = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(
                references: [
                    sessionBookmarkID: sessionReference,
                    recoveryBookmarkID: recoveryReference,
                ]
            ),
            files: LaunchFileServiceSpy(),
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(model.document.fileReference, recoveryReference)
    }

    func testNonemptyUntitledRecoveryRestoresEditedAndUnsaved() async throws {
        let documentID = UUID()
        let session = makeSession(
            documentID: documentID,
            hasUnsavedChanges: false,
            saveState: .untitled
        )
        let recovery = makeRecovery(documentID: documentID, text: "preserve me")
        let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        _ = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(),
            files: LaunchFileServiceSpy(),
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(model.document.storage.string, "preserve me")
        XCTAssertEqual(model.document.saveState, .edited)
        XCTAssertTrue(model.document.hasUnsavedChanges)
    }

    func testCleanFileBackedLaunchWithUnresolvedBookmarkOpensUntitledWithBanner() async throws {
        let documentID = UUID()
        let bookmarkID = UUID()
        let session = makeSession(
            documentID: documentID,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean
        )
        let repository = RecoveryRepositorySpy(session: session)
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        let source = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(),
            files: LaunchFileServiceSpy(),
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(source, .empty)
        assertEmptyUntitled(model.document)
        XCTAssertEqual(model.banner?.actions, [.reselectFile, .dismiss])
        let sessionWrites = await repository.sessionWrites
        XCTAssertEqual(sessionWrites.count, 1)
        XCTAssertNil(sessionWrites.first?.fileReferenceID)
        XCTAssertEqual(sessionWrites.first?.didCloseCleanly, false)
    }

    func testCleanFileBackedLaunchWithMissingFileOpensUntitledWithBanner() async throws {
        let documentID = UUID()
        let bookmarkID = UUID()
        let reference = ExternalFileReference(bookmarkID: bookmarkID, pathHint: "/Notes/File.md")
        let session = makeSession(
            documentID: documentID,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: false,
            saveState: .clean
        )
        let repository = RecoveryRepositorySpy(session: session)
        let files = LaunchFileServiceSpy(openError: .missing)
        let model = ApplicationModel()
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: VirtualRecoveryClock(),
            documentProvider: { id in model.document.id == id ? model.document : nil }
        )

        let source = try await model.restoreAtLaunch(
            repository: repository,
            bookmarks: BookmarkAccessSpy(references: [bookmarkID: reference]),
            files: files,
            recoveryCoordinator: coordinator,
            windowFrame: session.windowFrame
        )

        XCTAssertEqual(source, .empty)
        assertEmptyUntitled(model.document)
        XCTAssertEqual(model.banner?.actions, [.reselectFile, .dismiss])
        let openedReferences = await files.openedReferences
        XCTAssertEqual(openedReferences, [reference])
    }

    func testRecoveryWithUnresolvedBookmarkRestoresTextUntitledAndKeepsRecord() async throws {
        let documentID = UUID()
        let bookmarkID = UUID()
        let session = makeSession(
            documentID: documentID,
            fileReferenceID: bookmarkID,
            hasUnsavedChanges: true,
            saveState: .conflicted
        )
        let recovery = makeRecovery(
            documentID: documentID,
            documentGeneration: 4,
            fileReferenceID: bookmarkID,
            filePathHint: "/Notes/Missing.md",
            text: "preserve association",
            baseDiskHash: "base-hash"
        )
        let repository = RecoveryRepositorySpy(session: session, recoveries: [recovery])

        for launch in 1...2 {
            let model = ApplicationModel()
            let coordinator = RecoveryCoordinator(
                repository: repository,
                clock: VirtualRecoveryClock(),
                documentProvider: { id in model.document.id == id ? model.document : nil }
            )

            let source = try await model.restoreAtLaunch(
                repository: repository,
                bookmarks: BookmarkAccessSpy(),
                files: LaunchFileServiceSpy(),
                recoveryCoordinator: coordinator,
                windowFrame: session.windowFrame
            )

            XCTAssertEqual(source, .recovery(recovery), "launch \(launch)")
            let document = model.document
            XCTAssertEqual(document.id, documentID, "launch \(launch)")
            XCTAssertEqual(document.storage.string, "preserve association", "launch \(launch)")
            XCTAssertNil(document.fileReference, "launch \(launch)")
            XCTAssertEqual(document.displayName, "Untitled", "launch \(launch)")
            XCTAssertEqual(document.saveState, .edited, "launch \(launch)")
            XCTAssertTrue(document.hasUnsavedChanges, "launch \(launch)")
            XCTAssertNil(document.lastSavedHash, "launch \(launch)")
            XCTAssertNil(document.lastKnownDiskMTime, "launch \(launch)")
            XCTAssertEqual(model.banner?.actions, [.saveAs, .dismiss], "launch \(launch)")
        }

        let stored = await repository.storedRecovery(documentID: documentID)
        XCTAssertEqual(stored, recovery)
        let recoveryWrites = await repository.recoveryWrites
        XCTAssertEqual(recoveryWrites, [])
        let deleted = await repository.deletedRecoveryIDs
        XCTAssertEqual(deleted, [])
    }

    private func assertEmptyUntitled(
        _ document: DocumentSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(document.storage.string, "", file: file, line: line)
        XCTAssertNil(document.fileReference, file: file, line: line)
        XCTAssertEqual(document.displayName, "Untitled", file: file, line: line)
        XCTAssertEqual(document.saveState, .untitled, file: file, line: line)
        XCTAssertFalse(document.hasUnsavedChanges, file: file, line: line)
    }
}

private extension RecoveryCoordinatorTests {
    func waitForSleeperCount(
        _ count: Int,
        clock: VirtualRecoveryClock
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await clock.activeSleeperCount == count { return true }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(count) virtual recovery sleeper(s)")
        return false
    }

    func waitForRecoveryWrites(
        _ count: Int,
        repository: RecoveryRepositorySpy
    ) async {
        while await repository.recoveryWrites.count < count {
            await Task.yield()
        }
    }

    func makeSession(
        documentID: UUID,
        documentGeneration: Int? = nil,
        fileReferenceID: UUID? = nil,
        hasUnsavedChanges: Bool,
        saveState: DocumentSaveState,
        savedAt: Date = Date(timeIntervalSince1970: 10)
    ) -> SessionRecord {
        SessionRecord(
            schemaVersion: 1,
            documentID: documentID,
            documentGeneration: documentGeneration,
            fileReferenceID: fileReferenceID,
            displayName: fileReferenceID == nil ? "Untitled" : "File.md",
            saveState: saveState,
            hasUnsavedChanges: hasUnsavedChanges,
            selection: TextSelection(location: 2, length: 1),
            scrollOffsetY: 18,
            lineEnding: .lf,
            lastSavedHash: fileReferenceID == nil ? nil : "base-hash",
            lastKnownDiskMTime: fileReferenceID == nil ? nil : Date(timeIntervalSince1970: 40),
            windowFrame: CGRect(x: 1, y: 2, width: 820, height: 640),
            didCloseCleanly: true,
            savedAt: savedAt
        )
    }

    func makeRecovery(
        documentID: UUID,
        documentGeneration: Int? = nil,
        fileReferenceID: UUID? = nil,
        filePathHint: String? = nil,
        text: String,
        baseDiskHash: String? = nil,
        pendingSaveAs: PendingSaveAsRecord? = nil,
        savedAt: Date = Date(timeIntervalSince1970: 20)
    ) -> RecoveryRecord {
        RecoveryRecord(
            schemaVersion: 1,
            documentID: documentID,
            documentGeneration: documentGeneration,
            fileReferenceID: fileReferenceID,
            filePathHint: filePathHint,
            unsavedText: text,
            baseDiskHash: baseDiskHash,
            baseDiskMTime: nil,
            lineEnding: .lf,
            selection: TextSelection(location: 1, length: 2),
            scrollOffsetY: 31,
            savedAt: savedAt,
            pendingSaveAs: pendingSaveAs
        )
    }
}

@MainActor
private final class DocumentLookup: @unchecked Sendable {
    private let documents: [UUID: DocumentSession]

    init(_ documents: [DocumentSession]) {
        self.documents = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
    }

    func document(id: UUID) -> DocumentSession? {
        documents[id]
    }
}

private actor VirtualRecoveryClock: RecoveryClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var now: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var activeSleeperCount: Int { sleepers.count }
    var activeDeadlines: [Duration] {
        sleepers.values.map(\.deadline).sorted()
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                sleepers[id] = Sleeper(deadline: now + duration, continuation: continuation)
                resumeSatisfiedCountWaiters()
            }
        } onCancel: {
            Task { await self.cancelSleeper(id: id) }
        }
    }

    func waitForSleepers(_ count: Int) async {
        guard sleepers.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func advance(by duration: Duration) {
        now += duration
        let ready = sleepers.filter { $0.value.deadline <= now }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }

    private func cancelSleeper(id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        sleeper.continuation.resume(throwing: CancellationError())
    }

    private func resumeSatisfiedCountWaiters() {
        let ready = countWaiters.filter { sleepers.count >= $0.count }
        countWaiters.removeAll { sleepers.count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}

private actor RecoveryRepositorySpy: SessionPersisting {
    private let session: SessionRecord?
    private var recoveries: [UUID: RecoveryRecord]
    private(set) var sessionWrites: [SessionRecord] = []
    private(set) var recoveryWrites: [RecoveryRecord] = []
    private(set) var deletedRecoveryIDs: [UUID] = []
    private var suspendedRecoveryWriteCount: Int
    private var recoveryWriteEntries = 0
    private var recoveryWriteEntryWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var suspendedRecoveryWriteContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        session: SessionRecord? = nil,
        recoveries: [RecoveryRecord] = [],
        suspendedRecoveryWriteCount: Int = 0
    ) {
        self.session = session
        self.recoveries = Dictionary(uniqueKeysWithValues: recoveries.map { ($0.documentID, $0) })
        self.suspendedRecoveryWriteCount = suspendedRecoveryWriteCount
    }

    var storedRecoveries: [RecoveryRecord] {
        recoveries.values.sorted { $0.documentID.uuidString < $1.documentID.uuidString }
    }

    func loadSession() async throws -> SessionRecord? { session }

    func writeSession(_ record: SessionRecord) async throws {
        sessionWrites.append(record)
    }

    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? {
        recoveries[documentID]
    }

    func loadAllRecovery() async throws -> [RecoveryRecord] { storedRecoveries }

    func writeRecovery(_ record: RecoveryRecord) async throws {
        recoveryWriteEntries += 1
        resumeSatisfiedRecoveryWriteEntryWaiters()
        if suspendedRecoveryWriteCount > 0 {
            suspendedRecoveryWriteCount -= 1
            await withCheckedContinuation { continuation in
                suspendedRecoveryWriteContinuations.append(continuation)
            }
        }
        recoveries[record.documentID] = record
        recoveryWrites.append(record)
    }

    func waitForRecoveryWriteEntries(_ count: Int) async {
        guard recoveryWriteEntries < count else { return }
        await withCheckedContinuation { continuation in
            recoveryWriteEntryWaiters.append((count, continuation))
        }
    }

    func releaseNextRecoveryWrite() {
        guard !suspendedRecoveryWriteContinuations.isEmpty else { return }
        suspendedRecoveryWriteContinuations.removeFirst().resume()
    }

    func storedRecovery(documentID: UUID) -> RecoveryRecord? {
        recoveries[documentID]
    }

    func deleteRecovery(documentID: UUID) async throws {
        recoveries.removeValue(forKey: documentID)
        deletedRecoveryIDs.append(documentID)
    }

    private func resumeSatisfiedRecoveryWriteEntryWaiters() {
        let ready = recoveryWriteEntryWaiters.filter { recoveryWriteEntries >= $0.count }
        recoveryWriteEntryWaiters.removeAll { recoveryWriteEntries >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}

private actor BookmarkAccessSpy: BookmarkAccessing {
    private let references: [UUID: ExternalFileReference]
    private let deniedReferenceIDs: Set<UUID>

    init(
        references: [UUID: ExternalFileReference] = [:],
        deniedReferenceIDs: Set<UUID> = []
    ) {
        self.references = references
        self.deniedReferenceIDs = deniedReferenceIDs
    }

    func storeSelection(_ url: URL) async throws -> ExternalFileReference {
        ExternalFileReference(bookmarkID: UUID(), pathHint: url.path)
    }

    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference? {
        if deniedReferenceIDs.contains(bookmarkID) {
            throw BookmarkStoreError.accessDenied
        }
        return references[bookmarkID]
    }

    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken {
        ScopedAccessToken(id: UUID(), url: URL(fileURLWithPath: reference.pathHint))
    }

    func endAccess(_ token: ScopedAccessToken) async {}
    func refresh(_ token: ScopedAccessToken) async throws {}
    func forget(_ reference: ExternalFileReference) async throws {}
}

private actor LaunchFileServiceSpy: FileServicing {
    private let openResult: FileOpenResult?
    private let openError: LaunchFileServiceError?
    private(set) var openedReferences: [ExternalFileReference] = []

    init(
        openResult: FileOpenResult? = nil,
        openError: LaunchFileServiceError? = nil
    ) {
        self.openResult = openResult
        self.openError = openError
    }

    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        openedReferences.append(reference)
        if let openError { throw openError }
        guard let openResult else { throw LaunchFileServiceError.missingResult }
        return openResult
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        throw LaunchFileServiceError.unsupported
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        throw LaunchFileServiceError.unsupported
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        toSelectedURL url: URL
    ) async throws -> FileSaveResult {
        throw LaunchFileServiceError.unsupported
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        throw LaunchFileServiceError.unsupported
    }
}

private enum LaunchFileServiceError: Error {
    case missingResult
    case missing
    case unsupported
}
