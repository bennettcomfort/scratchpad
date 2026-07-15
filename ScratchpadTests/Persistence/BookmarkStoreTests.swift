import Foundation
import XCTest
@testable import Scratchpad

final class BookmarkStoreTests: XCTestCase {
    func testStoreSelectionPersistsBookmarkBeforeReturningReference() async throws {
        let fixture = try makeFixture()
        let selectedURL = fixture.root
            .appending(path: "folder", directoryHint: .isDirectory)
            .appending(path: "..")
            .appending(path: "Prompt.md")

        let first = try await fixture.store.storeSelection(selectedURL)
        let second = try await fixture.store.storeSelection(selectedURL.standardizedFileURL)

        XCTAssertEqual(first.bookmarkID, second.bookmarkID)
        XCTAssertEqual(first.pathHint, selectedURL.standardizedFileURL.path)
        XCTAssertEqual(second.pathHint, selectedURL.standardizedFileURL.path)
        let collection = try persistedCollection(in: fixture)
        XCTAssertEqual(collection.schemaVersion, 1)
        XCTAssertEqual(collection.records.count, 1)
        XCTAssertEqual(collection.records[0].id, first.bookmarkID)
        XCTAssertEqual(collection.records[0].pathHint, selectedURL.standardizedFileURL.path)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.writes.count, 2)
        XCTAssertEqual(snapshot.writes.map(\.destination), [
            fixture.paths.bookmarkCollection,
            fixture.paths.bookmarkCollection
        ])
    }

    func testBeginAndEndAccessBalanceExactlyOnce() async throws {
        let fixture = try makeFixture()
        let record = try makeRecord(path: fixture.root.appending(path: "Balanced.md").path)
        try seed(BookmarkCollection(schemaVersion: 1, records: [record]), in: fixture)
        fixture.client.setResolution(
            ResolvedBookmark(url: URL(filePath: record.pathHint), isStale: false),
            for: record.bookmarkData
        )

        let token = try await fixture.store.beginAccess(reference(for: record))
        await fixture.store.endAccess(token)
        await fixture.store.endAccess(token)

        let snapshot = fixture.client.snapshot()
        XCTAssertEqual(snapshot.starts, [URL(filePath: record.pathHint)])
        XCTAssertEqual(snapshot.stops, [URL(filePath: record.pathHint)])
    }

    func testStaleResolutionRefreshesAndPersistsBookmark() async throws {
        let recorder = LockedEventRecorder()
        let fixture = try makeFixture(recorder: recorder)
        let oldData = Data("old-bookmark".utf8)
        let record = try makeRecord(
            bookmarkData: oldData,
            path: fixture.root.appending(path: "Moved.md").path
        )
        try seed(BookmarkCollection(schemaVersion: 1, records: [record]), in: fixture)
        let resolvedURL = fixture.root.appending(path: "Resolved.md")
        fixture.client.setResolution(
            ResolvedBookmark(url: resolvedURL, isStale: true),
            for: oldData
        )

        let token = try await fixture.store.beginAccess(reference(for: record))

        let collection = try persistedCollection(in: fixture)
        let refreshed = try XCTUnwrap(collection.records.first)
        XCTAssertEqual(refreshed.bookmarkData, fixture.client.bookmarkData(for: resolvedURL))
        XCTAssertEqual(refreshed.pathHint, resolvedURL.standardizedFileURL.path)
        XCTAssertEqual(recorder.snapshot().suffix(3), ["create", "write", "start"])
        await fixture.store.endAccess(token)
    }

    func testUnresolvableBookmarkNeverFallsBackToPathHint() async throws {
        let fixture = try makeFixture()
        let readableURL = fixture.root.appending(path: "Readable.md")
        try Data("must not be read".utf8).write(to: readableURL)
        let record = try makeRecord(path: readableURL.path)
        try seed(BookmarkCollection(schemaVersion: 1, records: [record]), in: fixture)
        fixture.client.failResolution(for: record.bookmarkData)

        do {
            _ = try await fixture.store.beginAccess(reference(for: record))
            XCTFail("Expected reselection requirement")
        } catch let error as BookmarkStoreError {
            XCTAssertEqual(error, .reselectionRequired)
        }

        let snapshot = fixture.client.snapshot()
        XCTAssertTrue(snapshot.directURLReads.isEmpty)
        XCTAssertTrue(snapshot.starts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: readableURL), Data("must not be read".utf8))
    }

    func testForgetRefusesWhileTokenIsActive() async throws {
        let fixture = try makeFixture()
        let record = try makeRecord(path: fixture.root.appending(path: "Active.md").path)
        try seed(BookmarkCollection(schemaVersion: 1, records: [record]), in: fixture)
        fixture.client.setResolution(
            ResolvedBookmark(url: URL(filePath: record.pathHint), isStale: false),
            for: record.bookmarkData
        )
        let reference = reference(for: record)
        let token = try await fixture.store.beginAccess(reference)

        do {
            try await fixture.store.forget(reference)
            XCTFail("Expected active bookmark refusal")
        } catch let error as BookmarkStoreError {
            XCTAssertEqual(error, .bookmarkInUse)
        }
        XCTAssertEqual(try persistedCollection(in: fixture).records.map(\.id), [record.id])

        await fixture.store.endAccess(token)
        try await fixture.store.forget(reference)
        XCTAssertTrue(try persistedCollection(in: fixture).records.isEmpty)
    }

    func testCorruptBookmarkCollectionIsQuarantined() async throws {
        let corruptFixture = try makeFixture()
        let corruptData = Data("{not-json".utf8)
        try corruptData.write(to: corruptFixture.paths.bookmarkCollection)

        let missing = try await corruptFixture.store.reference(for: UUID())

        XCTAssertNil(missing)
        let corruptSnapshot = await corruptFixture.writer.snapshot()
        XCTAssertEqual(corruptSnapshot.quarantines.count, 1)
        XCTAssertEqual(corruptSnapshot.quarantines[0].source, corruptFixture.paths.bookmarkCollection)
        XCTAssertEqual(try Data(contentsOf: corruptSnapshot.quarantines[0].destination), corruptData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptFixture.paths.bookmarkCollection.path))

        let unsupportedFixture = try makeFixture()
        let unsupportedData = try JSONEncoder().encode(
            BookmarkCollection(schemaVersion: 2, records: [])
        )
        try unsupportedData.write(to: unsupportedFixture.paths.bookmarkCollection)

        let unsupportedReference = try await unsupportedFixture.store.reference(for: UUID())
        XCTAssertNil(unsupportedReference)
        let unsupportedSnapshot = await unsupportedFixture.writer.snapshot()
        XCTAssertEqual(unsupportedSnapshot.quarantines.map(\.source), [
            unsupportedFixture.paths.bookmarkCollection
        ])

        let failingFixture = try makeFixture(quarantineFails: true)
        try corruptData.write(to: failingFixture.paths.bookmarkCollection)
        do {
            _ = try await failingFixture.store.reference(for: UUID())
            XCTFail("Expected quarantine failure")
        } catch let error as BookmarkStoreError {
            guard case let .quarantineFailed(source, _) = error else {
                return XCTFail("Expected quarantineFailed, got \(error)")
            }
            XCTAssertEqual(source, failingFixture.paths.bookmarkCollection)
        }
        XCTAssertEqual(try Data(contentsOf: failingFixture.paths.bookmarkCollection), corruptData)
        let failingSnapshot = await failingFixture.writer.snapshot()
        XCTAssertEqual(failingSnapshot.quarantines.map(\.source), [
            failingFixture.paths.bookmarkCollection
        ])
        XCTAssertTrue(failingSnapshot.writes.isEmpty)
    }

    func testReferenceLookupUsesPersistedPathHintWithoutDirectAccess() async throws {
        let fixture = try makeFixture()
        let record = try makeRecord(path: "/Volumes/Unavailable/Prompt.md")
        try seed(BookmarkCollection(schemaVersion: 1, records: [record]), in: fixture)

        let loaded = try await fixture.store.reference(for: record.id)

        XCTAssertEqual(loaded, reference(for: record))
        let snapshot = fixture.client.snapshot()
        XCTAssertTrue(snapshot.creations.isEmpty)
        XCTAssertTrue(snapshot.resolutions.isEmpty)
        XCTAssertTrue(snapshot.starts.isEmpty)
        XCTAssertTrue(snapshot.directURLReads.isEmpty)
    }

    func testFailedEarlierWriteCannotRollbackLaterSuccessfulMutation() async throws {
        let fixture = try makeFixture(suspendedWriteNumber: 1)
        let firstURL = fixture.root.appending(path: "First.md")
        let secondURL = fixture.root.appending(path: "Second.md")
        let first = Task { try await fixture.store.storeSelection(firstURL) }
        await fixture.writer.waitUntilWriteSuspends()
        let secondStarted = AsyncSignal()
        let second = Task {
            await secondStarted.signal()
            return try await fixture.store.storeSelection(secondURL)
        }
        await secondStarted.wait()
        await yieldToConcurrentOperations()

        await fixture.writer.resumeSuspendedWrite(failing: true)

        guard case .failure = await first.result else {
            return XCTFail("Expected the earlier write to fail")
        }
        let secondReference = try await second.value
        let missingReference = try await fixture.store.reference(for: UUID())
        let retainedReference = try await fixture.store.reference(
            for: secondReference.bookmarkID
        )
        XCTAssertNil(missingReference)
        XCTAssertEqual(
            retainedReference,
            secondReference
        )
        let collection = try persistedCollection(in: fixture)
        XCTAssertEqual(collection.records.map(\.id), [secondReference.bookmarkID])
    }

    func testSecondBeginAccessWaitsForStaleRefreshPersistence() async throws {
        let fixture = try makeFixture(suspendedWriteNumber: 1)
        let oldData = Data("stale-bookmark".utf8)
        let record = try makeRecord(
            bookmarkData: oldData,
            path: fixture.root.appending(path: "Stale.md").path
        )
        try seed(BookmarkCollection(schemaVersion: 1, records: [record]), in: fixture)
        let resolvedURL = fixture.root.appending(path: "Resolved.md")
        fixture.client.setResolution(
            ResolvedBookmark(url: resolvedURL, isStale: true),
            for: oldData
        )
        let externalReference = reference(for: record)
        let first = Task { try await fixture.store.beginAccess(externalReference) }
        await fixture.writer.waitUntilWriteSuspends()
        let secondStarted = AsyncSignal()
        let second = Task {
            await secondStarted.signal()
            return try await fixture.store.beginAccess(externalReference)
        }
        await secondStarted.wait()
        await yieldToConcurrentOperations()

        XCTAssertTrue(fixture.client.snapshot().starts.isEmpty)
        await fixture.writer.resumeSuspendedWrite(failing: false)

        let firstToken = try await first.value
        let secondToken = try await second.value
        XCTAssertEqual(fixture.client.snapshot().starts.count, 2)
        await fixture.store.endAccess(firstToken)
        await fixture.store.endAccess(secondToken)
        XCTAssertEqual(fixture.client.snapshot().stops.count, 2)
    }

    func testConcurrentCorruptLoadsQuarantineExactlyOnce() async throws {
        let fixture = try makeFixture(suspendFirstQuarantine: true)
        try Data("{corrupt".utf8).write(to: fixture.paths.bookmarkCollection)
        let first = Task { try await fixture.store.reference(for: UUID()) }
        await fixture.writer.waitUntilQuarantineSuspends()
        let secondStarted = AsyncSignal()
        let second = Task {
            await secondStarted.signal()
            return try await fixture.store.reference(for: UUID())
        }
        await secondStarted.wait()
        await yieldToConcurrentOperations()

        let suspendedSnapshot = await fixture.writer.snapshot()
        XCTAssertEqual(suspendedSnapshot.quarantines.count, 1)
        await fixture.writer.resumeSuspendedQuarantine()

        let firstReference = try await first.value
        let secondReference = try await second.value
        let completedSnapshot = await fixture.writer.snapshot()
        XCTAssertNil(firstReference)
        XCTAssertNil(secondReference)
        XCTAssertEqual(completedSnapshot.quarantines.count, 1)
    }

    func testDuplicateStandardizedPathIdentitiesAreQuarantined() async throws {
        let fixture = try makeFixture()
        let first = try makeRecord(
            id: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            path: fixture.root.appending(path: "folder/../Prompt.md").path
        )
        let second = try makeRecord(
            id: "11111111-2222-3333-4444-555555555555",
            path: fixture.root.appending(path: "Prompt.md").path
        )
        try seed(BookmarkCollection(schemaVersion: 1, records: [first, second]), in: fixture)

        let loaded = try await fixture.store.reference(for: first.id)

        XCTAssertNil(loaded)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.quarantines.map(\.source), [fixture.paths.bookmarkCollection])
    }
}

private extension BookmarkStoreTests {
    struct Fixture {
        let root: URL
        let paths: ApplicationSupportPaths
        let writer: BookmarkWriterSpy
        let client: SecurityScopedBookmarkClientFake
        let store: BookmarkStore
    }

    func makeFixture(
        recorder: LockedEventRecorder = LockedEventRecorder(),
        quarantineFails: Bool = false,
        suspendedWriteNumber: Int? = nil,
        suspendFirstQuarantine: Bool = false
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "bookmark-store-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let paths = ApplicationSupportPaths(root: root)
        try paths.createDirectories(using: .default)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let writer = BookmarkWriterSpy(
            recorder: recorder,
            quarantineFails: quarantineFails,
            suspendedWriteNumber: suspendedWriteNumber,
            suspendFirstQuarantine: suspendFirstQuarantine
        )
        let client = SecurityScopedBookmarkClientFake(recorder: recorder)
        return Fixture(
            root: root,
            paths: paths,
            writer: writer,
            client: client,
            store: BookmarkStore(
                paths: paths,
                writer: writer,
                client: client,
                now: { Date(timeIntervalSince1970: 1_721_000_000) }
            )
        )
    }

    func makeRecord(
        id: String = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        bookmarkData: Data = Data("bookmark".utf8),
        path: String
    ) throws -> BookmarkRecord {
        BookmarkRecord(
            id: try XCTUnwrap(UUID(uuidString: id)),
            bookmarkData: bookmarkData,
            pathHint: path,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func reference(for record: BookmarkRecord) -> ExternalFileReference {
        ExternalFileReference(bookmarkID: record.id, pathHint: record.pathHint)
    }

    func seed(_ collection: BookmarkCollection, in fixture: Fixture) throws {
        try JSONEncoder().encode(collection).write(to: fixture.paths.bookmarkCollection)
    }

    func persistedCollection(in fixture: Fixture) throws -> BookmarkCollection {
        try JSONDecoder().decode(
            BookmarkCollection.self,
            from: Data(contentsOf: fixture.paths.bookmarkCollection)
        )
    }

    func yieldToConcurrentOperations() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }
}

private actor BookmarkWriterSpy: AtomicFileWriting {
    struct Write: Sendable {
        let data: Data
        let destination: URL
    }

    struct Quarantine: Sendable {
        let source: URL
        let destination: URL
    }

    struct Snapshot: Sendable {
        let writes: [Write]
        let quarantines: [Quarantine]
    }

    private let recorder: LockedEventRecorder
    private let quarantineFails: Bool
    private let suspendedWriteNumber: Int?
    private let suspendFirstQuarantine: Bool
    private var writes: [Write] = []
    private var quarantines: [Quarantine] = []
    private var writeAttempt = 0
    private var suspendedWriteContinuation: CheckedContinuation<Void, Never>?
    private var writeSuspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendedWriteShouldFail = false
    private var suspendedQuarantineContinuation: CheckedContinuation<Void, Never>?
    private var quarantineSuspensionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        recorder: LockedEventRecorder,
        quarantineFails: Bool,
        suspendedWriteNumber: Int?,
        suspendFirstQuarantine: Bool
    ) {
        self.recorder = recorder
        self.quarantineFails = quarantineFails
        self.suspendedWriteNumber = suspendedWriteNumber
        self.suspendFirstQuarantine = suspendFirstQuarantine
    }

    func write(_ data: Data, to destination: URL) async throws {
        recorder.append("write")
        writeAttempt += 1
        if writeAttempt == suspendedWriteNumber {
            writeSuspensionWaiters.forEach { $0.resume() }
            writeSuspensionWaiters = []
            await withCheckedContinuation { continuation in
                suspendedWriteContinuation = continuation
            }
            if suspendedWriteShouldFail {
                throw TestFailure.write
            }
        }
        try data.write(to: destination)
        writes.append(Write(data: data, destination: destination))
    }

    func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func quarantine(_ source: URL, as destination: URL) async throws {
        quarantines.append(Quarantine(source: source, destination: destination))
        if suspendFirstQuarantine, quarantines.count == 1 {
            quarantineSuspensionWaiters.forEach { $0.resume() }
            quarantineSuspensionWaiters = []
            await withCheckedContinuation { continuation in
                suspendedQuarantineContinuation = continuation
            }
        }
        if quarantineFails {
            throw TestFailure.quarantine
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func snapshot() -> Snapshot {
        Snapshot(writes: writes, quarantines: quarantines)
    }

    func waitUntilWriteSuspends() async {
        guard suspendedWriteContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            writeSuspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedWrite(failing: Bool) {
        suspendedWriteShouldFail = failing
        let continuation = suspendedWriteContinuation
        suspendedWriteContinuation = nil
        continuation?.resume()
    }

    func waitUntilQuarantineSuspends() async {
        guard suspendedQuarantineContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            quarantineSuspensionWaiters.append(continuation)
        }
    }

    func resumeSuspendedQuarantine() {
        let continuation = suspendedQuarantineContinuation
        suspendedQuarantineContinuation = nil
        continuation?.resume()
    }
}

private final class SecurityScopedBookmarkClientFake: SecurityScopedBookmarkClient, @unchecked Sendable {
    struct Snapshot {
        let creations: [URL]
        let resolutions: [Data]
        let starts: [URL]
        let stops: [URL]
        let directURLReads: [URL]
    }

    private let lock = NSLock()
    private let recorder: LockedEventRecorder
    private var resolvedByData: [Data: ResolvedBookmark] = [:]
    private var failingData: Set<Data> = []
    private var creations: [URL] = []
    private var resolutions: [Data] = []
    private var starts: [URL] = []
    private var stops: [URL] = []
    private var directURLReads: [URL] = []

    init(recorder: LockedEventRecorder) {
        self.recorder = recorder
    }

    func bookmarkData(for url: URL) -> Data {
        Data("bookmark:\(url.standardizedFileURL.path)".utf8)
    }

    func setResolution(_ resolution: ResolvedBookmark, for data: Data) {
        lock.withLock { resolvedByData[data] = resolution }
    }

    func failResolution(for data: Data) {
        lock.withLock { _ = failingData.insert(data) }
    }

    func create(for url: URL) throws -> Data {
        recorder.append("create")
        return lock.withLock {
            creations.append(url)
            let data = bookmarkData(for: url)
            resolvedByData[data] = ResolvedBookmark(url: url, isStale: false)
            return data
        }
    }

    func resolve(_ data: Data) throws -> ResolvedBookmark {
        try lock.withLock {
            resolutions.append(data)
            guard !failingData.contains(data), let resolution = resolvedByData[data] else {
                throw TestFailure.resolution
            }
            return resolution
        }
    }

    func startAccessing(_ url: URL) -> Bool {
        recorder.append("start")
        lock.withLock { starts.append(url) }
        return true
    }

    func stopAccessing(_ url: URL) {
        recorder.append("stop")
        lock.withLock { stops.append(url) }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                creations: creations,
                resolutions: resolutions,
                starts: starts,
                stops: stops,
                directURLReads: directURLReads
            )
        }
    }
}

private final class LockedEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.withLock { events.append(event) }
    }

    func snapshot() -> [String] {
        lock.withLock { events }
    }
}

private actor AsyncSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignaled = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private enum TestFailure: Error {
    case resolution
    case quarantine
    case write
}
