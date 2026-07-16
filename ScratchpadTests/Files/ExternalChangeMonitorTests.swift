import Foundation
import XCTest
@testable import Scratchpad

@MainActor
final class ExternalChangeMonitorTests: XCTestCase {
    func testMonitorInspectsOncePerVirtualSecond() async throws {
        let clock = ExternalMonitorVirtualClock()
        let files = ExternalMonitorFileServiceFake()
        let document = makeFileBackedDocument(text: "base")
        let monitor = ExternalChangeMonitor(fileService: files, clock: clock)

        monitor.start(document: document) { _, _, _ in }
        await clock.waitForSleepers(1)
        var inspectCount = await files.inspectCount
        XCTAssertEqual(inspectCount, 0)

        await clock.advance(by: .milliseconds(999))
        inspectCount = await files.inspectCount
        XCTAssertEqual(inspectCount, 0)
        await clock.advance(by: .milliseconds(1))
        await files.waitForInspectEntries(1)
        await clock.waitForSleepers(1)
        inspectCount = await files.inspectCount
        XCTAssertEqual(inspectCount, 1)

        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(2)
        await clock.waitForSleepers(1)
        inspectCount = await files.inspectCount
        XCTAssertEqual(inspectCount, 2)
        monitor.stop()
    }

    func testReplacingDocumentDiscardsOldIdentityResult() async throws {
        let clock = ExternalMonitorVirtualClock()
        let files = ExternalMonitorFileServiceFake(suspendInspectCount: 1)
        let repository = ExternalMonitorRepositoryFake()
        let original = makeFileBackedDocument(text: "original")
        let model = makeModel(
            document: original,
            files: files,
            repository: repository,
            clock: clock
        )

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(1)

        await model.requestNewDocument()
        let replacement = model.document
        let replacementBeforeOldResult = replacement.snapshot()
        await files.releaseNextInspect(
            with: .changed(
                contentHash: "external-hash",
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        )
        await Task.yield()

        XCTAssertFalse(replacement === original)
        assertDocument(replacement, equals: replacementBeforeOldResult)
        let openCount = await files.openCount
        XCTAssertEqual(openCount, 0)
    }

    func testCleanChangedFileReloadsThroughWholeTextReplacement() async throws {
        let clock = ExternalMonitorVirtualClock()
        let reference = makeReference()
        let files = ExternalMonitorFileServiceFake(
            suspendInspectCount: 1,
            openResult: FileOpenResult(
                reference: reference,
                text: "external text",
                displayName: "note.md",
                lineEnding: .lf,
                contentHash: "external-hash",
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        )
        let document = makeFileBackedDocument(text: "base", reference: reference)
        document.updateSelection(TextSelection(location: 4, length: 0))
        let model = makeModel(document: document, files: files, clock: clock)

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(1)
        await files.releaseNextInspect(
            with: .changed(
                contentHash: "external-hash",
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        )
        await clock.waitForSleepers(1)

        XCTAssertEqual(document.storage.string, "external text")
        XCTAssertEqual(document.saveState, .clean)
        XCTAssertFalse(document.hasUnsavedChanges)
        XCTAssertEqual(document.lastSavedHash, "external-hash")
        XCTAssertEqual(document.selection, TextSelection(location: 4, length: 0))
        let openCount = await files.openCount
        XCTAssertEqual(openCount, 1)
    }

    func testEditedChangedFileEntersConflictWithoutReplacingText() async throws {
        let clock = ExternalMonitorVirtualClock()
        let files = ExternalMonitorFileServiceFake(suspendInspectCount: 1)
        let document = makeFileBackedDocument(text: "local edits")
        document.noteUserEdit()
        let model = makeModel(document: document, files: files, clock: clock)

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(1)
        await files.releaseNextInspect(
            with: .changed(
                contentHash: "external-hash",
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        )
        await clock.waitForSleepers(1)

        XCTAssertEqual(document.storage.string, "local edits")
        XCTAssertEqual(document.saveState, .conflicted)
        XCTAssertTrue(document.hasUnsavedChanges)
        let openCount = await files.openCount
        XCTAssertEqual(openCount, 0)
    }

    func testMissingAndDeniedStatusesMapToDeletedAndReadOnlyStates() async throws {
        let cases: [(ExternalFileStatus, DocumentSaveState, Bool, [BannerAction]?)] = [
            (.missing, .deleted, true, [.saveAs, .dismiss]),
            (.readOnly, .readOnly, false, [.saveAs, .dismiss]),
            (.accessRequiresReselection, .readOnly, false, [.reselectFile, .dismiss])
        ]

        for (status, expectedState, expectedUnsaved, expectedActions) in cases {
            let clock = ExternalMonitorVirtualClock()
            let files = ExternalMonitorFileServiceFake(suspendInspectCount: 1)
            let document = makeFileBackedDocument(text: "preserved")
            let model = makeModel(document: document, files: files, clock: clock)

            model.startExternalChangeMonitoring()
            await clock.waitForSleepers(1)
            await clock.advance(by: .seconds(1))
            await files.waitForInspectEntries(1)
            await files.releaseNextInspect(with: status)
            await clock.waitForSleepers(1)

            XCTAssertEqual(document.storage.string, "preserved")
            XCTAssertEqual(document.saveState, expectedState)
            XCTAssertEqual(document.hasUnsavedChanges, expectedUnsaved)
            XCTAssertEqual(model.banner?.actions, expectedActions)
        }
    }
}

@MainActor
private func makeModel(
    document: DocumentSession,
    files: ExternalMonitorFileServiceFake,
    repository: ExternalMonitorRepositoryFake = ExternalMonitorRepositoryFake(),
    clock: ExternalMonitorVirtualClock
) -> ApplicationModel {
    ApplicationModel(
        document: document,
        servicesFactory: {
            ApplicationServices(
                repository: repository,
                bookmarks: ExternalMonitorBookmarkFake(),
                files: files,
                recoveryClock: clock
            )
        }
    )
}

@MainActor
private func makeFileBackedDocument(
    text: String,
    reference: ExternalFileReference = makeReference()
) -> DocumentSession {
    DocumentSession(
        text: text,
        fileReference: reference,
        displayName: "note.md",
        saveState: .clean,
        hasUnsavedChanges: false,
        lastSavedHash: "base-hash",
        lastKnownDiskMTime: Date(timeIntervalSince1970: 1)
    )
}

private func makeReference() -> ExternalFileReference {
    ExternalFileReference(bookmarkID: UUID(), pathHint: "/tmp/note.md")
}

@MainActor
private func assertDocument(
    _ document: DocumentSession,
    equals snapshot: DocumentSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(document.id, snapshot.documentID, file: file, line: line)
    XCTAssertEqual(document.generation, snapshot.generation, file: file, line: line)
    XCTAssertEqual(document.storage.string, snapshot.text, file: file, line: line)
    XCTAssertEqual(document.fileReference, snapshot.fileReference, file: file, line: line)
    XCTAssertEqual(document.saveState, snapshot.saveState, file: file, line: line)
    XCTAssertEqual(document.hasUnsavedChanges, snapshot.hasUnsavedChanges, file: file, line: line)
    XCTAssertEqual(document.selection, snapshot.selection, file: file, line: line)
    XCTAssertEqual(document.scrollOffsetY, snapshot.scrollOffsetY, file: file, line: line)
    XCTAssertEqual(document.lineEnding, snapshot.lineEnding, file: file, line: line)
    XCTAssertEqual(document.lastSavedHash, snapshot.lastSavedHash, file: file, line: line)
    XCTAssertEqual(document.lastKnownDiskMTime, snapshot.lastKnownDiskMTime, file: file, line: line)
}

private actor ExternalMonitorVirtualClock: RecoveryClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var now: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

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
            Task { await self.cancelSleeper(id) }
        }
    }

    func waitForSleepers(_ count: Int) async {
        guard sleepers.count < count else { return }
        await withCheckedContinuation { countWaiters.append((count, $0)) }
    }

    func advance(by duration: Duration) {
        now += duration
        let ready = sleepers.filter { $0.value.deadline <= now }
        for (id, sleeper) in ready {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }

    private func cancelSleeper(_ id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        sleeper.continuation.resume(throwing: CancellationError())
    }

    private func resumeSatisfiedCountWaiters() {
        let ready = countWaiters.filter { sleepers.count >= $0.0 }
        countWaiters.removeAll { sleepers.count >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
}

private actor ExternalMonitorFileServiceFake: FileServicing {
    private var suspendedInspects: Int
    private var inspectEntries = 0
    private var inspectWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var inspectContinuations: [CheckedContinuation<ExternalFileStatus, Never>] = []
    private let configuredOpenResult: FileOpenResult?
    private(set) var openCount = 0

    init(
        suspendInspectCount: Int = 0,
        openResult: FileOpenResult? = nil
    ) {
        self.suspendedInspects = suspendInspectCount
        self.configuredOpenResult = openResult
    }

    var inspectCount: Int { inspectEntries }

    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        openCount += 1
        guard let configuredOpenResult else { throw ExternalMonitorFakeError.unconfigured }
        return configuredOpenResult
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        throw ExternalMonitorFakeError.unconfigured
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        throw ExternalMonitorFakeError.unconfigured
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        inspectEntries += 1
        resumeSatisfiedInspectWaiters()
        guard suspendedInspects > 0 else { return .unchanged }
        suspendedInspects -= 1
        return await withCheckedContinuation { inspectContinuations.append($0) }
    }

    func waitForInspectEntries(_ count: Int) async {
        guard inspectEntries < count else { return }
        await withCheckedContinuation { inspectWaiters.append((count, $0)) }
    }

    func releaseNextInspect(with status: ExternalFileStatus) {
        guard !inspectContinuations.isEmpty else { return }
        inspectContinuations.removeFirst().resume(returning: status)
    }

    private func resumeSatisfiedInspectWaiters() {
        let ready = inspectWaiters.filter { inspectEntries >= $0.0 }
        inspectWaiters.removeAll { inspectEntries >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
}

private actor ExternalMonitorRepositoryFake: SessionPersisting {
    func loadSession() async throws -> SessionRecord? { nil }
    func writeSession(_ record: SessionRecord) async throws {}
    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }
    func writeRecovery(_ record: RecoveryRecord) async throws {}
    func deleteRecovery(documentID: UUID) async throws {}
}

private actor ExternalMonitorBookmarkFake: BookmarkAccessing {
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

private enum ExternalMonitorFakeError: Error {
    case unconfigured
}
