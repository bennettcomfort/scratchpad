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
        await waitUntil { events == ["decision"] }

        gate.resume()
        await waitUntil { events == ["decision", "close"] }
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
        await waitUntil { events == ["decision"] }
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
        await waitUntil { model.pendingDecision != nil }
        model.resolvePendingDecision(with: .save)
        await waitUntil { recorder.events.last == "reply(true)" }

        XCTAssertEqual(
            recorder.events,
            ["decision", "recovery flush", "session(false)", "session(true)", "reply(true)"]
        )
    }

    func testTerminationFailureRepliesFalseAndKeepsAppOpen() async {
        for (failure, expected) in [
            (LifecycleFailure.recovery, ["decision", "recovery flush", "reply(false)"]),
            (.nonCleanSession, ["decision", "recovery flush", "session(false)", "reply(false)"])
        ] {
            let recorder = LifecycleEventRecorder()
            let model = makeLifecycleModel(recorder: recorder, failure: failure)
            let delegate = AppDelegate(
                terminationReply: { _, result in recorder.append("reply(\(result))") }
            )
            delegate.attach(model: model)

            XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
            await waitUntil { model.pendingDecision != nil }
            model.resolvePendingDecision(with: .save)
            await waitUntil { recorder.events.last == "reply(false)" }

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
        await waitUntil { requestCount == 1 }
        gate.resume()
        await waitUntil { events.last == "reply(true)" }

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(events.filter { $0.hasPrefix("reply") }, ["reply(true)"])
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
        await waitUntil { cleanValues.count == 1 }

        XCTAssertEqual(cleanValues, [false])
        XCTAssertEqual(presentationCount, 0)
        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        XCTAssertEqual(presentationCount, 1)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
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

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum LifecycleFailure: Error {
    case recovery
    case nonCleanSession
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
        recorder.append("session(\(record.didCloseCleanly))")
        if failure == .nonCleanSession, !record.didCloseCleanly {
            throw LifecycleFailure.nonCleanSession
        }
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

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        .unchanged
    }
}

private actor LifecycleClock: RecoveryClock {
    func sleep(for duration: Duration) async throws {}
}
