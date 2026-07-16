import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class ApplicationLifecycleTests: XCTestCase {
    func testWindowCloseReturnsFalseUntilAsyncDecisionSucceeds() async {
        let gate = LifecycleGate()
        var events: [String] = []
        let closeHarness = WindowCloseHarness()
        let coordinator = WindowCloseCoordinator(
            requestClose: {
                events.append("decision")
                await gate.wait()
                return true
            },
            closeWindow: {
                events.append("close")
                closeHarness.invokeClose()
            }
        )
        closeHarness.coordinator = coordinator

        XCTAssertFalse(coordinator.windowShouldClose())
        XCTAssertFalse(coordinator.windowShouldClose())
        guard await waitUntil({ events == ["decision"] }) else {
            gate.resume()
            return
        }

        gate.resume()
        guard await waitUntil({ events == ["decision", "close"] }) else { return }
        XCTAssertEqual(closeHarness.results, [true])
        XCTAssertEqual(events, ["decision", "close"])
    }

    func testWindowCloseFailureNeverClosesWindow() async {
        var events: [String] = []
        let coordinator = WindowCloseCoordinator(
            requestClose: {
                events.append("decision")
                return false
            },
            closeWindow: { events.append("close") }
        )

        XCTAssertFalse(coordinator.windowShouldClose())
        guard await waitUntil({ events == ["decision"] }) else { return }
        await Task.yield()

        XCTAssertEqual(events, ["decision"])
    }

    func testTerminationReturnsLaterAndRepliesTrueAfterFlush() async {
        let recorder = LifecycleEventRecorder()
        let model = makeLifecycleModel(recorder: recorder)
        let delegate = AppDelegate(
            terminationReply: { _, result in recorder.append("reply(\(result))") }
        )
        delegate.attach(model: model)

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        guard await waitUntil({ model.pendingDecision != nil }) else { return }
        model.resolvePendingDecision(with: .save)
        guard await waitUntil({ recorder.events.last == "reply(true)" }) else { return }

        XCTAssertEqual(
            recorder.events,
            [
                "decision", "recovery flush", "recovery flush", "session(false)",
                "session(false)", "session(true)", "reply(true)"
            ]
        )
    }

    func testTerminationFailureRepliesFalseAndKeepsAppOpen() async {
        for (failure, expected) in [
            (LifecycleFailure.recovery, ["decision", "recovery flush", "reply(false)"]),
            (
                .nonCleanSession,
                [
                    "decision", "recovery flush", "recovery flush",
                    "session(false) failed", "reply(false)"
                ]
            ),
            (
                .cleanSession,
                [
                    "decision", "recovery flush", "recovery flush", "session(false)",
                    "session(false)", "session(true) failed", "reply(false)"
                ]
            )
        ] {
            let recorder = LifecycleEventRecorder()
            let model = makeLifecycleModel(recorder: recorder, failure: failure)
            let delegate = AppDelegate(
                terminationReply: { _, result in recorder.append("reply(\(result))") }
            )
            delegate.attach(model: model)

            XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
            guard await waitUntil({ model.pendingDecision != nil }) else { return }
            model.resolvePendingDecision(with: .save)
            guard await waitUntil({ recorder.events.last == "reply(false)" }) else { return }

            XCTAssertEqual(recorder.events, expected)
            XCTAssertFalse(recorder.events.contains("session(true)"))
            XCTAssertEqual(model.document.storage.string, "latest text")
        }
    }

    func testRepeatedTerminationRequestsJoinOneTask() async {
        let gate = LifecycleGate()
        var events: [String] = []
        var requestCount = 0
        let delegate = AppDelegate(
            terminationReply: { _, result in events.append("reply(\(result))") }
        )
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateCancel)
        delegate.attachLifecycle(
            requestTermination: {
                requestCount += 1
                events.append("decision")
                await gate.wait()
                events.append("recovery flush")
                events.append("session(false)")
                events.append("session(true)")
                return true
            },
            requestResignActiveFlush: { _ in true },
            presentResignActiveFailure: {}
        )

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        guard await waitUntil({ requestCount == 1 }) else {
            gate.resume()
            return
        }
        gate.resume()
        guard await waitUntil({ events.last == "reply(true)" }) else { return }

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(events.filter { $0.hasPrefix("reply") }, ["reply(true)"])
    }

    func testTerminationWaitsForActiveResignFlushThatIgnoresCancellation() async {
        let resignGate = LifecycleGate()
        var events: [String] = []
        let delegate = AppDelegate(
            terminationReply: { _, result in events.append("reply(\(result))") }
        )
        delegate.attachLifecycle(
            requestTermination: {
                events.append("termination")
                return true
            },
            requestResignActiveFlush: { _ in
                events.append("resign-start")
                await resignGate.wait()
                events.append("session(false)")
                return true
            },
            presentResignActiveFailure: {}
        )

        delegate.applicationDidResignActive(
            Notification(name: NSApplication.didResignActiveNotification)
        )
        guard await resignGate.waitUntilEntered() else {
            resignGate.resume()
            return
        }
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        await Task.yield()
        XCTAssertEqual(events, ["resign-start"])

        resignGate.resume()
        guard await waitUntil({ events.last == "reply(true)" }) else { return }
        XCTAssertEqual(events, ["resign-start", "session(false)", "termination", "reply(true)"])
    }

    func testResignActiveDoesNotStartWhileTerminationIsActive() async {
        let terminationGate = LifecycleGate()
        var events: [String] = []
        let delegate = AppDelegate(
            terminationReply: { _, result in events.append("reply(\(result))") }
        )
        delegate.attachLifecycle(
            requestTermination: {
                events.append("termination")
                await terminationGate.wait()
                return true
            },
            requestResignActiveFlush: { _ in
                events.append("resign")
                return true
            },
            presentResignActiveFailure: {}
        )

        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        guard await terminationGate.waitUntilEntered() else {
            terminationGate.resume()
            return
        }
        delegate.applicationDidResignActive(
            Notification(name: NSApplication.didResignActiveNotification)
        )
        await Task.yield()
        XCTAssertEqual(events, ["termination"])

        terminationGate.resume()
        guard await waitUntil({ events.last == "reply(true)" }) else { return }
        XCTAssertEqual(events, ["termination", "reply(true)"])
    }

    func testResignActiveFlushUsesDidCloseCleanlyFalse() async {
        var cleanValues: [Bool] = []
        var presentationCount = 0
        let delegate = AppDelegate(terminationReply: { _, _ in })
        delegate.attachLifecycle(
            requestTermination: { true },
            requestResignActiveFlush: { didCloseCleanly in
                cleanValues.append(didCloseCleanly)
                return false
            },
            presentResignActiveFailure: { presentationCount += 1 }
        )

        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        guard await waitUntil({ cleanValues.count == 1 }) else { return }

        XCTAssertEqual(cleanValues, [false])
        XCTAssertEqual(presentationCount, 0)
        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        XCTAssertEqual(presentationCount, 1)
    }

    func testPersistenceRetryPreservesStateWithoutInvokingFileSaveOrSaveAs() async {
        let repository = RetryLifecycleRepository()
        let files = RetryFileService()
        let document = DocumentSession(
            text: "latest recovery text",
            fileReference: ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/tmp/retry.md"
            ),
            displayName: "retry.md",
            saveState: .edited,
            hasUnsavedChanges: true,
            generation: 1
        )
        let model = ApplicationModel(
            document: document,
            servicesFactory: {
                ApplicationServices(
                    repository: repository,
                    bookmarks: LifecycleBookmarkStore(),
                    files: files,
                    recoveryClock: LifecycleClock()
                )
            },
            windowFrameProvider: { CGRect(x: 20, y: 30, width: 820, height: 640) }
        )

        let initialFlushSucceeded = await model.flushLifecycleState(didCloseCleanly: false)
        XCTAssertFalse(initialFlushSucceeded)
        XCTAssertEqual(
            model.banner?.actions,
            [
                .retry(.preserveCurrentDocument),
                .openRecoveryFolder,
                .dismiss,
            ]
        )

        await model.retryBannerOperation(.preserveCurrentDocument)

        let recoveryWriteCount = await repository.recoveryWriteCount
        let sessionWriteCount = await repository.sessionWriteCount
        let saveCallCount = await files.saveCallCount
        let saveAsCallCount = await files.saveAsCallCount
        XCTAssertEqual(recoveryWriteCount, 2)
        XCTAssertEqual(sessionWriteCount, 2)
        XCTAssertEqual(saveCallCount, 0)
        XCTAssertEqual(saveAsCallCount, 0)
        XCTAssertNil(model.banner)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            await Task.yield()
        }
        XCTFail("Timed out waiting for deterministic lifecycle condition")
        return false
    }

    private func makeLifecycleModel(
        recorder: LifecycleEventRecorder,
        failure: LifecycleFailure? = nil
    ) -> ApplicationModel {
        let document = DocumentSession(
            text: "latest text",
            fileReference: ExternalFileReference(
                bookmarkID: UUID(),
                pathHint: "/tmp/lifecycle.md"
            ),
            displayName: "lifecycle.md",
            saveState: .edited,
            hasUnsavedChanges: true,
            generation: 1,
            lastSavedHash: "base",
            lastKnownDiskMTime: Date(timeIntervalSince1970: 1)
        )
        let repository = LifecycleRepository(recorder: recorder, failure: failure)
        let decisionCoordinator = DocumentDecisionCoordinator { _ in
            recorder.append("decision")
        }
        return ApplicationModel(
            document: document,
            servicesFactory: {
                ApplicationServices(
                    repository: repository,
                    bookmarks: LifecycleBookmarkStore(),
                    files: LifecycleFileService(),
                    recoveryClock: LifecycleClock()
                )
            },
            decisionCoordinator: decisionCoordinator,
            windowFrameProvider: { CGRect(x: 0, y: 0, width: 820, height: 640) }
        )
    }
}

@MainActor
private final class WindowCloseHarness {
    weak var coordinator: WindowCloseCoordinator?
    private(set) var results: [Bool] = []

    func invokeClose() {
        results.append(coordinator?.windowShouldClose() ?? false)
    }
}

@MainActor
private final class LifecycleGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didEnter = false
    private var shouldProceed = false

    func wait() async {
        didEnter = true
        guard !shouldProceed else {
            shouldProceed = false
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async -> Bool {
        for _ in 0..<1_000 {
            if didEnter { return true }
            await Task.yield()
        }
        XCTFail("Timed out waiting for lifecycle gate entry")
        return false
    }

    func resume() {
        guard let continuation else {
            shouldProceed = true
            return
        }
        self.continuation = nil
        continuation.resume()
    }
}

private enum LifecycleFailure: Error {
    case recovery
    case nonCleanSession
    case cleanSession
}

private final class LifecycleEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] { lock.withLock { storage } }

    func append(_ event: String) {
        lock.withLock { storage.append(event) }
    }
}

private actor LifecycleRepository: SessionPersisting {
    private let recorder: LifecycleEventRecorder
    private let failure: LifecycleFailure?

    init(recorder: LifecycleEventRecorder, failure: LifecycleFailure?) {
        self.recorder = recorder
        self.failure = failure
    }

    func loadSession() async throws -> SessionRecord? { nil }

    func writeSession(_ record: SessionRecord) async throws {
        if failure == .cleanSession, record.didCloseCleanly {
            recorder.append("session(true) failed")
            throw LifecycleFailure.cleanSession
        }
        if failure == .nonCleanSession, !record.didCloseCleanly {
            recorder.append("session(false) failed")
            throw LifecycleFailure.nonCleanSession
        }
        recorder.append("session(\(record.didCloseCleanly))")
    }

    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }

    func writeRecovery(_ record: RecoveryRecord) async throws {
        recorder.append("recovery flush")
        if failure == .recovery { throw LifecycleFailure.recovery }
    }

    func deleteRecovery(documentID: UUID) async throws {}
}

private actor LifecycleBookmarkStore: BookmarkAccessing {
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

private actor LifecycleFileService: FileServicing {
    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        throw LifecycleFailure.recovery
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        guard let reference = snapshot.fileReference else {
            throw FileServiceError.missingFileReference
        }
        return FileSaveResult(
            documentID: snapshot.documentID,
            initiatingGeneration: snapshot.generation,
            reference: reference,
            displayName: "lifecycle.md",
            lineEnding: snapshot.lineEnding,
            contentHash: "saved",
            modificationDate: Date(timeIntervalSince1970: 2)
        )
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        throw LifecycleFailure.recovery
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        toSelectedURL url: URL
    ) async throws -> FileSaveResult {
        throw LifecycleFailure.recovery
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        .unchanged
    }
}

private actor LifecycleClock: RecoveryClock {
    func sleep(for duration: Duration) async throws {}
}

private actor RetryLifecycleRepository: SessionPersisting {
    private(set) var recoveryWriteCount = 0
    private(set) var sessionWriteCount = 0

    func loadSession() async throws -> SessionRecord? { nil }

    func writeSession(_ record: SessionRecord) async throws {
        sessionWriteCount += 1
        if sessionWriteCount == 1 {
            throw LifecycleFailure.nonCleanSession
        }
    }

    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }
    func writeRecovery(_ record: RecoveryRecord) async throws {
        recoveryWriteCount += 1
    }
    func deleteRecovery(documentID: UUID) async throws {}
}

private actor RetryFileService: FileServicing {
    private(set) var saveCallCount = 0
    private(set) var saveAsCallCount = 0

    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        throw LifecycleFailure.recovery
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        saveCallCount += 1
        throw LifecycleFailure.recovery
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        saveAsCallCount += 1
        throw LifecycleFailure.recovery
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        toSelectedURL url: URL
    ) async throws -> FileSaveResult {
        saveAsCallCount += 1
        throw LifecycleFailure.recovery
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        .unchanged
    }
}
