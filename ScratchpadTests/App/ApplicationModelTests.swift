import Foundation
import XCTest
@testable import Scratchpad

@MainActor
final class ApplicationModelTests: XCTestCase {
    func testModelOwnsExactlyTheInjectedDocument() {
        let document = DocumentSession(text: "owned")
        let model = ApplicationModel(document: document)

        XCTAssertTrue(model.document === document)
        XCTAssertEqual(model.document.storage.string, "owned")
    }

    func testLaunchGateRemainsClosedUntilUncleanSessionWriteCompletes() async throws {
        let repository = LaunchRepositoryFake(suspendSessionWrites: true)
        let model = ApplicationModel(
            launchState: .restoring,
            servicesFactory: { makeLaunchServices(repository: repository) }
        )

        let restoration = Task {
            await model.restoreCurrentLaunchAttempt(
                windowFrame: CGRect(x: 0, y: 0, width: 820, height: 640)
            )
        }
        await repository.waitForSessionWriteEntries(1)
        XCTAssertEqual(model.launchState, .restoring)
        await repository.releaseNextSessionWrite()
        await restoration.value

        XCTAssertEqual(model.launchState, .ready)
        let writes = await repository.sessionWrites
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(writes.allSatisfy { !$0.didCloseCleanly })
    }

    func testLaunchFailureKeepsGateClosedAndRetrySucceeds() async throws {
        let repository = LaunchRepositoryFake(sessionWriteFailures: 1)
        let model = ApplicationModel(
            launchState: .restoring,
            servicesFactory: { makeLaunchServices(repository: repository) }
        )
        let frame = CGRect(x: 0, y: 0, width: 820, height: 640)

        await model.restoreCurrentLaunchAttempt(windowFrame: frame)
        XCTAssertEqual(
            model.launchState,
            .failed(message: "Scratchpad couldn't restore this session safely.")
        )
        let failedAttempt = model.launchAttempt

        model.requestLaunchRetry()
        XCTAssertEqual(model.launchAttempt, failedAttempt + 1)
        XCTAssertEqual(model.launchState, .restoring)
        await model.restoreCurrentLaunchAttempt(windowFrame: frame)

        XCTAssertEqual(model.launchState, .ready)
        let writes = await repository.sessionWrites
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(writes.allSatisfy { !$0.didCloseCleanly })
    }

    func testLaunchContainmentFlushPreservesLoadedSessionFrame() async throws {
        let savedFrame = CGRect(x: 173, y: 91, width: 930, height: 711)
        let preRestorationFrame = CGRect(x: 0, y: 0, width: 820, height: 640)
        let session = DocumentSession().sessionRecord(
            windowFrame: savedFrame,
            didCloseCleanly: true
        )
        let repository = LaunchRepositoryFake(session: session)
        let model = ApplicationModel(
            launchState: .restoring,
            servicesFactory: { makeLaunchServices(repository: repository) }
        )

        await model.restoreCurrentLaunchAttempt(windowFrame: preRestorationFrame)

        let writes = await repository.sessionWrites
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.windowFrame, savedFrame)
        XCTAssertEqual(model.restoredWindowFrame, savedFrame)
    }

    func testCurrentDocumentEditSchedulesRecoveryThroughLaunchCoordinator() async throws {
        let repository = LaunchRepositoryFake()
        let model = ApplicationModel(
            launchState: .restoring,
            servicesFactory: { makeLaunchServices(repository: repository) }
        )
        await model.restoreCurrentLaunchAttempt(
            windowFrame: CGRect(x: 0, y: 0, width: 820, height: 640)
        )
        XCTAssertEqual(model.launchState, .ready)

        model.document.storage.setAttributedString(
            NSAttributedString(string: "typed in production editor")
        )
        model.document.noteUserEdit()
        model.handleCurrentDocumentEdit(model.document)
        await repository.waitForRecoveryWrites(1)

        let writes = await repository.recoveryWrites
        XCTAssertEqual(writes.map(\.unsavedText), ["typed in production editor"])
    }

    func testDirtyDocumentStateChangeReschedulesRecoveryWithLatestMetadata() async throws {
        let repository = LaunchRepositoryFake()
        let model = ApplicationModel(
            launchState: .restoring,
            servicesFactory: { makeLaunchServices(repository: repository) }
        )
        await model.restoreCurrentLaunchAttempt(
            windowFrame: CGRect(x: 0, y: 0, width: 820, height: 640)
        )

        model.document.storage.setAttributedString(NSAttributedString(string: "dirty recovery"))
        model.document.noteUserEdit()
        model.handleCurrentDocumentEdit(model.document)
        await repository.waitForRecoveryWrites(1)
        let generationAfterEdit = model.document.generation

        model.document.updateSelection(TextSelection(location: 5, length: 3))
        model.document.updateScrollOffset(91)
        model.handleCurrentDocumentStateChange(model.document)
        await repository.waitForRecoveryWrites(2)

        let writes = await repository.recoveryWrites
        XCTAssertEqual(writes.last?.unsavedText, "dirty recovery")
        XCTAssertEqual(writes.last?.selection, TextSelection(location: 5, length: 3))
        XCTAssertEqual(writes.last?.scrollOffsetY, 91)
        XCTAssertEqual(model.document.generation, generationAfterEdit)
        XCTAssertTrue(model.document.hasUnsavedChanges)
    }

    func testCleanDocumentStateChangeDoesNotCreateRecovery() async throws {
        let repository = LaunchRepositoryFake()
        let model = ApplicationModel(
            launchState: .restoring,
            servicesFactory: { makeLaunchServices(repository: repository) }
        )
        await model.restoreCurrentLaunchAttempt(
            windowFrame: CGRect(x: 0, y: 0, width: 820, height: 640)
        )

        model.document.updateSelection(TextSelection(location: 0, length: 0))
        model.document.updateScrollOffset(17)
        model.handleCurrentDocumentStateChange(model.document)
        for _ in 0..<100 { await Task.yield() }

        let writes = await repository.recoveryWrites
        XCTAssertEqual(writes, [])
        XCTAssertEqual(model.document.generation, 0)
        XCTAssertFalse(model.document.hasUnsavedChanges)
    }
}

@MainActor
private func makeLaunchServices(repository: any SessionPersisting) -> ApplicationServices {
    ApplicationServices(
        repository: repository,
        bookmarks: LaunchBookmarkFake(),
        files: LaunchFileFake(),
        recoveryClock: LaunchClockFake()
    )
}

private actor LaunchRepositoryFake: SessionPersisting {
    private let session: SessionRecord?
    private var remainingSessionWriteFailures: Int
    private var shouldSuspendSessionWrites: Bool
    private var sessionWriteEntries = 0
    private var sessionWriteEntryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var sessionWriteContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var sessionWrites: [SessionRecord] = []
    private(set) var recoveryWrites: [RecoveryRecord] = []
    private var recoveryWriteWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        session: SessionRecord? = nil,
        suspendSessionWrites: Bool = false,
        sessionWriteFailures: Int = 0
    ) {
        self.session = session
        self.shouldSuspendSessionWrites = suspendSessionWrites
        self.remainingSessionWriteFailures = sessionWriteFailures
    }

    func loadSession() async throws -> SessionRecord? { session }

    func writeSession(_ record: SessionRecord) async throws {
        sessionWrites.append(record)
        sessionWriteEntries += 1
        resumeSatisfiedEntryWaiters()
        if shouldSuspendSessionWrites {
            shouldSuspendSessionWrites = false
            await withCheckedContinuation { sessionWriteContinuations.append($0) }
        }
        if remainingSessionWriteFailures > 0 {
            remainingSessionWriteFailures -= 1
            throw LaunchRepositoryError.writeFailed
        }
    }

    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }
    func writeRecovery(_ record: RecoveryRecord) async throws {
        recoveryWrites.append(record)
        let ready = recoveryWriteWaiters.filter { recoveryWrites.count >= $0.0 }
        recoveryWriteWaiters.removeAll { recoveryWrites.count >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
    func deleteRecovery(documentID: UUID) async throws {}

    func waitForSessionWriteEntries(_ count: Int) async {
        guard sessionWriteEntries < count else { return }
        await withCheckedContinuation { sessionWriteEntryWaiters.append((count, $0)) }
    }

    func releaseNextSessionWrite() {
        guard !sessionWriteContinuations.isEmpty else { return }
        sessionWriteContinuations.removeFirst().resume()
    }

    func waitForRecoveryWrites(_ count: Int) async {
        guard recoveryWrites.count < count else { return }
        await withCheckedContinuation { recoveryWriteWaiters.append((count, $0)) }
    }

    private func resumeSatisfiedEntryWaiters() {
        let ready = sessionWriteEntryWaiters.filter { sessionWriteEntries >= $0.0 }
        sessionWriteEntryWaiters.removeAll { sessionWriteEntries >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
}

private enum LaunchRepositoryError: Error {
    case writeFailed
}

private actor LaunchBookmarkFake: BookmarkAccessing {
    func storeSelection(_ url: URL) async throws -> ExternalFileReference {
        ExternalFileReference(bookmarkID: UUID(), pathHint: url.path)
    }
    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference? { nil }
    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken {
        ScopedAccessToken(id: UUID(), url: URL(fileURLWithPath: reference.pathHint))
    }
    func endAccess(_ token: ScopedAccessToken) async {}
    func refresh(_ token: ScopedAccessToken) async throws {}
    func forget(_ reference: ExternalFileReference) async throws {}
}

private actor LaunchFileFake: FileServicing {
    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        throw LaunchRepositoryError.writeFailed
    }
    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        throw LaunchRepositoryError.writeFailed
    }
    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        throw LaunchRepositoryError.writeFailed
    }
    func saveAs(
        _ snapshot: DocumentSnapshot,
        toSelectedURL url: URL
    ) async throws -> FileSaveResult {
        throw LaunchRepositoryError.writeFailed
    }
    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        throw LaunchRepositoryError.writeFailed
    }
}

private struct LaunchClockFake: RecoveryClock {
    func sleep(for duration: Duration) async throws {}
}
