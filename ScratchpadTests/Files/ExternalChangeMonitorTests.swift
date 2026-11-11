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

    func testRestartCancelsDeliveryWaitingForActiveOperation() async throws {
        let clock = ExternalMonitorVirtualClock()
        let files = ExternalMonitorFileServiceFake(suspendSaveCount: 1)
        let document = makeFileBackedDocument(text: "base")
        let model = makeModel(document: document, files: files, clock: clock)

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        let save = Task { await model.save() }
        await files.waitForSaveEntries(1)
        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(1)
        await waitForIdleWaiterCount(1, in: model)
        XCTAssertEqual(idleWaiterCount(in: model), 1)

        model.startExternalChangeMonitoring()
        await waitForIdleWaiterCount(0, in: model)
        XCTAssertEqual(idleWaiterCount(in: model), 0)
        await clock.waitForSleepers(1)
        let inspectCount = await files.inspectCount
        XCTAssertEqual(inspectCount, 1)

        await files.releaseNextSave()
        _ = await save.value
    }

    func testRestartCancelsSuspendedCleanReloadBeforeMutation() async throws {
        let clock = ExternalMonitorVirtualClock()
        let reference = makeReference()
        let files = ExternalMonitorFileServiceFake(
            suspendInspectCount: 1,
            suspendOpenCount: 1,
            openResult: FileOpenResult(
                reference: reference,
                text: "stale external text",
                displayName: "note.md",
                lineEnding: .lf,
                contentHash: "external-hash",
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        )
        let document = makeFileBackedDocument(text: "base", reference: reference)
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
        await files.waitForOpenEntries(1)

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        await files.releaseNextOpen()
        await waitForOperationState(.idle, in: model)

        XCTAssertEqual(model.operationState, .idle)
        XCTAssertEqual(document.storage.string, "base")
        XCTAssertEqual(document.saveState, .clean)
        XCTAssertFalse(document.hasUnsavedChanges)
        XCTAssertEqual(document.lastSavedHash, "base-hash")
    }

    func testOpeningFileStartsMonitoringAutomatically() async throws {
        let clock = ExternalMonitorVirtualClock()
        let reference = makeReference()
        let files = ExternalMonitorFileServiceFake(
            openResult: FileOpenResult(
                reference: reference,
                text: "opened",
                displayName: "note.md",
                lineEnding: .lf,
                contentHash: "base-hash",
                modificationDate: Date(timeIntervalSince1970: 1)
            )
        )
        let model = makeModel(
            document: DocumentSession(),
            files: files,
            clock: clock,
            panelProvider: ExternalMonitorPanelFake()
        )

        await model.requestOpen()
        await clock.waitForSleepers(1)
        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(1)

        XCTAssertEqual(model.document.storage.string, "opened")
        let inspectCount = await files.inspectCount
        XCTAssertEqual(inspectCount, 1)
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
        let reference = makeReference()
        let files = ExternalMonitorFileServiceFake(
            suspendInspectCount: 1,
            suspendOpenCount: 1,
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
        await files.waitForOpenEntries(1)
        document.storage.setAttributedString(NSAttributedString(string: "local edits"))
        document.noteUserEdit()
        await files.releaseNextOpen()
        await clock.waitForSleepers(1)

        XCTAssertEqual(document.storage.string, "local edits")
        XCTAssertEqual(document.saveState, .conflicted)
        XCTAssertTrue(document.hasUnsavedChanges)
        let openCount = await files.openCount
        XCTAssertEqual(openCount, 1)
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

    func testPersistentMissingFileWritesRecoveryOnceWithoutStarvation() async throws {
        let clock = ExternalMonitorVirtualClock()
        let files = ExternalMonitorFileServiceFake(steadyStatus: .missing)
        let repository = ExternalMonitorRepositoryFake()
        let document = makeFileBackedDocument(text: "kept while missing")
        let model = makeModel(
            document: document,
            files: files,
            repository: repository,
            clock: clock
        )

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        await advanceMonitorTick(1, clock: clock, files: files, sleepers: 2)
        await advanceMonitorTick(2, clock: clock, files: files, sleepers: 2)
        await clock.advance(by: .seconds(1))
        await assertRecoveryWrites(1, in: repository)
        await files.waitForInspectEntries(3)
        await clock.waitForSleepers(1)
        for tick in 4...10 {
            await advanceMonitorTick(tick, clock: clock, files: files, sleepers: 1)
        }

        let writes = await repository.recoveryWrites
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(writes.first?.unsavedText, "kept while missing")
        XCTAssertEqual(document.saveState, .deleted)
        XCTAssertTrue(document.hasUnsavedChanges)
    }

    func testEditDuringPersistentConflictReachesRecovery() async throws {
        let clock = ExternalMonitorVirtualClock()
        let files = ExternalMonitorFileServiceFake(
            steadyStatus: .changed(
                contentHash: "external-hash",
                modificationDate: Date(timeIntervalSince1970: 2)
            )
        )
        let repository = ExternalMonitorRepositoryFake()
        let document = makeFileBackedDocument(text: "base")
        document.storage.setAttributedString(NSAttributedString(string: "local edits"))
        document.noteUserEdit()
        let model = makeModel(
            document: document,
            files: files,
            repository: repository,
            clock: clock
        )

        model.startExternalChangeMonitoring()
        await clock.waitForSleepers(1)
        await advanceMonitorTick(1, clock: clock, files: files, sleepers: 2)
        await advanceMonitorTick(2, clock: clock, files: files, sleepers: 2)
        await clock.advance(by: .seconds(1))
        await assertRecoveryWrites(1, in: repository)
        await files.waitForInspectEntries(3)
        await clock.waitForSleepers(1)

        document.storage.setAttributedString(
            NSAttributedString(string: "edited during conflict")
        )
        document.noteUserEdit()
        model.handleCurrentDocumentEdit(document)
        await clock.waitForSleepers(2)
        await advanceMonitorTick(4, clock: clock, files: files, sleepers: 2)
        await clock.advance(by: .seconds(1))
        await assertRecoveryWrites(2, in: repository)
        await files.waitForInspectEntries(5)
        await clock.waitForSleepers(1)
        for tick in 6...7 {
            await advanceMonitorTick(tick, clock: clock, files: files, sleepers: 1)
        }

        let writes = await repository.recoveryWrites
        XCTAssertEqual(writes.map(\.unsavedText), ["local edits", "edited during conflict"])
        XCTAssertEqual(document.storage.string, "edited during conflict")
        XCTAssertEqual(document.saveState, .conflicted)
    }

    private func advanceMonitorTick(
        _ tick: Int,
        clock: ExternalMonitorVirtualClock,
        files: ExternalMonitorFileServiceFake,
        sleepers: Int
    ) async {
        await clock.advance(by: .seconds(1))
        await files.waitForInspectEntries(tick)
        await clock.waitForSleepers(sleepers)
    }

    private func assertRecoveryWrites(
        _ count: Int,
        in repository: ExternalMonitorRepositoryFake
    ) async {
        let written = expectation(description: "\(count) recovery write(s)")
        Task {
            await repository.waitForRecoveryWrites(count)
            written.fulfill()
        }
        await fulfillment(of: [written], timeout: 2)
    }
}

@MainActor
private func makeModel(
    document: DocumentSession,
    files: ExternalMonitorFileServiceFake,
    repository: ExternalMonitorRepositoryFake = ExternalMonitorRepositoryFake(),
    clock: ExternalMonitorVirtualClock,
    panelProvider: (any FilePanelProviding)? = nil
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
        },
        panelProvider: panelProvider
    )
}

@MainActor
private func idleWaiterCount(in model: ApplicationModel) -> Int {
    let child = Mirror(reflecting: model).children.first {
        $0.label?.hasSuffix("idleOperationWaiters") == true
    }
    guard let child else { return -1 }
    return Mirror(reflecting: child.value).children.count
}

@MainActor
private func waitForIdleWaiterCount(_ count: Int, in model: ApplicationModel) async {
    for _ in 0..<100 where idleWaiterCount(in: model) != count {
        await Task.yield()
    }
}

@MainActor
private func waitForOperationState(
    _ state: DocumentOperationState,
    in model: ApplicationModel
) async {
    for _ in 0..<100 where model.operationState != state {
        await Task.yield()
    }
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
    private var suspendedOpens: Int
    private var suspendedSaves: Int
    private var inspectEntries = 0
    private var inspectWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var inspectContinuations: [CheckedContinuation<ExternalFileStatus, Never>] = []
    private var openEntries = 0
    private var openWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var openContinuations: [CheckedContinuation<Void, Never>] = []
    private var saveEntries = 0
    private var saveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var saveContinuations: [CheckedContinuation<Void, Never>] = []
    private let configuredOpenResult: FileOpenResult?
    private let steadyStatus: ExternalFileStatus
    private(set) var openCount = 0

    init(
        suspendInspectCount: Int = 0,
        suspendOpenCount: Int = 0,
        suspendSaveCount: Int = 0,
        openResult: FileOpenResult? = nil,
        steadyStatus: ExternalFileStatus = .unchanged
    ) {
        self.suspendedInspects = suspendInspectCount
        self.suspendedOpens = suspendOpenCount
        self.suspendedSaves = suspendSaveCount
        self.configuredOpenResult = openResult
        self.steadyStatus = steadyStatus
    }

    var inspectCount: Int { inspectEntries }

    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        openCount += 1
        openEntries += 1
        resumeSatisfiedOpenWaiters()
        if suspendedOpens > 0 {
            suspendedOpens -= 1
            await withCheckedContinuation { openContinuations.append($0) }
        }
        guard let configuredOpenResult else { throw ExternalMonitorFakeError.unconfigured }
        return configuredOpenResult
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        saveEntries += 1
        resumeSatisfiedSaveWaiters()
        if suspendedSaves > 0 {
            suspendedSaves -= 1
            await withCheckedContinuation { saveContinuations.append($0) }
        }
        throw ExternalMonitorFakeError.unconfigured
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        throw ExternalMonitorFakeError.unconfigured
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        toSelectedURL url: URL
    ) async throws -> FileSaveResult {
        throw ExternalMonitorFakeError.unconfigured
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        inspectEntries += 1
        resumeSatisfiedInspectWaiters()
        guard suspendedInspects > 0 else { return steadyStatus }
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

    func waitForOpenEntries(_ count: Int) async {
        guard openEntries < count else { return }
        await withCheckedContinuation { openWaiters.append((count, $0)) }
    }

    func releaseNextOpen() {
        guard !openContinuations.isEmpty else { return }
        openContinuations.removeFirst().resume()
    }

    func waitForSaveEntries(_ count: Int) async {
        guard saveEntries < count else { return }
        await withCheckedContinuation { saveWaiters.append((count, $0)) }
    }

    func releaseNextSave() {
        guard !saveContinuations.isEmpty else { return }
        saveContinuations.removeFirst().resume()
    }

    private func resumeSatisfiedInspectWaiters() {
        let ready = inspectWaiters.filter { inspectEntries >= $0.0 }
        inspectWaiters.removeAll { inspectEntries >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }

    private func resumeSatisfiedOpenWaiters() {
        let ready = openWaiters.filter { openEntries >= $0.0 }
        openWaiters.removeAll { openEntries >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }

    private func resumeSatisfiedSaveWaiters() {
        let ready = saveWaiters.filter { saveEntries >= $0.0 }
        saveWaiters.removeAll { saveEntries >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
}

@MainActor
private final class ExternalMonitorPanelFake: FilePanelProviding {
    func selectFileToOpen() async -> URL? {
        URL(fileURLWithPath: "/tmp/note.md")
    }

    func selectSaveDestination(suggestedName: String) async -> URL? { nil }
}

private actor ExternalMonitorRepositoryFake: SessionPersisting {
    private(set) var recoveryWrites: [RecoveryRecord] = []
    private var recoveryWriteWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func loadSession() async throws -> SessionRecord? { nil }
    func writeSession(_ record: SessionRecord) async throws {}
    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }
    func writeRecovery(_ record: RecoveryRecord) async throws {
        recoveryWrites.append(record)
        let ready = recoveryWriteWaiters.filter { recoveryWrites.count >= $0.0 }
        recoveryWriteWaiters.removeAll { recoveryWrites.count >= $0.0 }
        for waiter in ready { waiter.1.resume() }
    }
    func deleteRecovery(documentID: UUID) async throws {}

    func waitForRecoveryWrites(_ count: Int) async {
        guard recoveryWrites.count < count else { return }
        await withCheckedContinuation { recoveryWriteWaiters.append((count, $0)) }
    }
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
