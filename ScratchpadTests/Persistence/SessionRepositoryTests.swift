import Foundation
import XCTest
@testable import Scratchpad

final class SessionRepositoryTests: XCTestCase {
    func testSessionRoundTripsEveryField() async throws {
        let fixture = try makeFixture()
        let record = try makeSessionRecord()

        try await fixture.repository.writeSession(record)
        let loaded = try await fixture.repository.loadSession()

        let unwrapped = try XCTUnwrap(loaded)
        XCTAssertEqual(unwrapped.schemaVersion, record.schemaVersion)
        XCTAssertEqual(unwrapped.documentID, record.documentID)
        XCTAssertEqual(unwrapped.fileReferenceID, record.fileReferenceID)
        XCTAssertEqual(unwrapped.displayName, record.displayName)
        XCTAssertEqual(unwrapped.saveState, record.saveState)
        XCTAssertEqual(unwrapped.hasUnsavedChanges, record.hasUnsavedChanges)
        XCTAssertEqual(unwrapped.selection, record.selection)
        XCTAssertEqual(unwrapped.scrollOffsetY, record.scrollOffsetY)
        XCTAssertEqual(unwrapped.lineEnding, record.lineEnding)
        XCTAssertEqual(unwrapped.lastSavedHash, record.lastSavedHash)
        XCTAssertEqual(unwrapped.lastKnownDiskMTime, record.lastKnownDiskMTime)
        XCTAssertEqual(unwrapped.windowFrame, record.windowFrame)
        XCTAssertEqual(unwrapped.didCloseCleanly, record.didCloseCleanly)
        XCTAssertEqual(unwrapped.savedAt, record.savedAt)

        let data = try Data(contentsOf: fixture.paths.latestSession)
        try assertSortedJSON(data)
        XCTAssertEqual(try schemaVersion(in: data), SessionRepository.schemaVersion)
    }

    func testRecoveryRoundTripsEveryField() async throws {
        let fixture = try makeFixture()
        let record = try makeRecoveryRecord(
            documentID: "11111111-2222-3333-4444-555555555555",
            text: "unsaved\r\ntext"
        )

        try await fixture.repository.writeRecovery(record)
        let loaded = try await fixture.repository.loadRecovery(documentID: record.documentID)

        let unwrapped = try XCTUnwrap(loaded)
        XCTAssertEqual(unwrapped.schemaVersion, record.schemaVersion)
        XCTAssertEqual(unwrapped.documentID, record.documentID)
        XCTAssertEqual(unwrapped.fileReferenceID, record.fileReferenceID)
        XCTAssertEqual(unwrapped.filePathHint, record.filePathHint)
        XCTAssertEqual(unwrapped.unsavedText, record.unsavedText)
        XCTAssertEqual(unwrapped.baseDiskHash, record.baseDiskHash)
        XCTAssertEqual(unwrapped.baseDiskMTime, record.baseDiskMTime)
        XCTAssertEqual(unwrapped.lineEnding, record.lineEnding)
        XCTAssertEqual(unwrapped.selection, record.selection)
        XCTAssertEqual(unwrapped.scrollOffsetY, record.scrollOffsetY)
        XCTAssertEqual(unwrapped.savedAt, record.savedAt)

        let data = try Data(contentsOf: fixture.paths.recovery(documentID: record.documentID))
        try assertSortedJSON(data)
        XCTAssertEqual(try schemaVersion(in: data), SessionRepository.schemaVersion)
    }

    func testRecoveryFilesRemainIndependentByDocumentID() async throws {
        let fixture = try makeFixture()
        let first = try makeRecoveryRecord(
            documentID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            text: "first"
        )
        let second = try makeRecoveryRecord(
            documentID: "99999999-8888-7777-6666-555555555555",
            text: "second"
        )

        try await fixture.repository.writeRecovery(first)
        try await fixture.repository.writeRecovery(second)

        let loadedFirst = try await fixture.repository.loadRecovery(documentID: first.documentID)
        let loadedSecond = try await fixture.repository.loadRecovery(documentID: second.documentID)
        XCTAssertEqual(loadedFirst?.unsavedText, "first")
        XCTAssertEqual(loadedSecond?.unsavedText, "second")
        let all = try await fixture.repository.loadAllRecovery()
        XCTAssertEqual(Set(all.map(\.documentID)), Set([first.documentID, second.documentID]))
    }

    func testDeletingOneRecoveryDoesNotDeleteAnother() async throws {
        let fixture = try makeFixture()
        let first = try makeRecoveryRecord(
            documentID: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB",
            text: "delete"
        )
        let second = try makeRecoveryRecord(
            documentID: "CCCCCCCC-4444-5555-6666-DDDDDDDDDDDD",
            text: "retain"
        )
        try await fixture.repository.writeRecovery(first)
        try await fixture.repository.writeRecovery(second)

        try await fixture.repository.deleteRecovery(documentID: first.documentID)

        let loadedFirst = try await fixture.repository.loadRecovery(documentID: first.documentID)
        let loadedSecond = try await fixture.repository.loadRecovery(documentID: second.documentID)
        XCTAssertNil(loadedFirst)
        XCTAssertEqual(loadedSecond?.unsavedText, "retain")
    }

    func testUndecodableSessionIsQuarantinedAndReturnsNil() async throws {
        let fixture = try makeFixture()
        let invalidData = Data("{not-json".utf8)
        try invalidData.write(to: fixture.paths.latestSession)

        let loaded = try await fixture.repository.loadSession()

        XCTAssertNil(loaded)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.quarantines.count, 1)
        XCTAssertEqual(snapshot.quarantines[0].source, fixture.paths.latestSession)
        XCTAssertTrue(snapshot.quarantines[0].destination.lastPathComponent.hasSuffix("-latest-session.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.latestSession.path))
        XCTAssertEqual(try Data(contentsOf: snapshot.quarantines[0].destination), invalidData)
    }

    func testUnsupportedRecoverySchemaIsQuarantinedAndReturnsNil() async throws {
        let fixture = try makeFixture()
        let record = try makeRecoveryRecord(
            documentID: "12345678-1234-1234-1234-123456789ABC",
            text: "unsupported"
        )
        let source = fixture.paths.recovery(documentID: record.documentID)
        let unsupported = try JSONEncoder().encode(
            RecoveryRecord(
                schemaVersion: 2,
                documentID: record.documentID,
                fileReferenceID: record.fileReferenceID,
                filePathHint: record.filePathHint,
                unsavedText: record.unsavedText,
                baseDiskHash: record.baseDiskHash,
                baseDiskMTime: record.baseDiskMTime,
                lineEnding: record.lineEnding,
                selection: record.selection,
                scrollOffsetY: record.scrollOffsetY,
                savedAt: record.savedAt
            )
        )
        try unsupported.write(to: source)

        let loaded = try await fixture.repository.loadRecovery(documentID: record.documentID)

        XCTAssertNil(loaded)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.quarantines.map(\.source), [source])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testQuarantineFailurePreservesOriginalAndThrows() async throws {
        let fixture = try makeFixture(quarantineFails: true)
        let invalidData = Data("not a session".utf8)
        try invalidData.write(to: fixture.paths.latestSession)

        do {
            _ = try await fixture.repository.loadSession()
            XCTFail("Expected quarantine failure")
        } catch let error as SessionRepositoryError {
            guard case let .quarantineFailed(source, _) = error else {
                return XCTFail("Expected quarantineFailed, got \(error)")
            }
            XCTAssertEqual(source, fixture.paths.latestSession)
        }

        XCTAssertEqual(try Data(contentsOf: fixture.paths.latestSession), invalidData)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.quarantines.map(\.source), [fixture.paths.latestSession])
        XCTAssertFalse(snapshot.removals.contains(fixture.paths.latestSession))
    }

    func testMismatchedRecoveryDocumentIDIsQuarantinedWhenLoadedDirectly() async throws {
        let fixture = try makeFixture()
        let requestedID = try fixedUUID("AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")
        let record = try makeRecoveryRecord(
            documentID: "CCCCCCCC-4444-5555-6666-DDDDDDDDDDDD",
            text: "wrong identity"
        )
        let source = fixture.paths.recovery(documentID: requestedID)
        try JSONEncoder().encode(record).write(to: source)

        let loaded = try await fixture.repository.loadRecovery(documentID: requestedID)

        XCTAssertNil(loaded)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.quarantines.map(\.source), [source])
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testMismatchedRecoveryDocumentIDIsQuarantinedByLoadAll() async throws {
        let fixture = try makeFixture()
        let filenameID = try fixedUUID("11111111-AAAA-BBBB-CCCC-222222222222")
        let record = try makeRecoveryRecord(
            documentID: "33333333-DDDD-EEEE-FFFF-444444444444",
            text: "wrong identity"
        )
        let source = fixture.paths.recovery(documentID: filenameID)
        try JSONEncoder().encode(record).write(to: source)

        let loaded = try await fixture.repository.loadAllRecovery()

        XCTAssertTrue(loaded.isEmpty)
        let snapshot = await fixture.writer.snapshot()
        XCTAssertEqual(snapshot.quarantines.map(\.source), [source])
    }

    func testLoadAllRecoveryIgnoresNoncanonicalSibling() async throws {
        let fixture = try makeFixture()
        let record = try makeRecoveryRecord(
            documentID: "ABCDEFAB-1234-5678-9ABC-DEFABCDEFABC",
            text: "canonical"
        )
        try await fixture.repository.writeRecovery(record)
        let canonical = fixture.paths.recovery(documentID: record.documentID)
        let noncanonical = fixture.paths.recoveryDirectory.appending(
            path: "document-\(record.documentID.uuidString.lowercased()).bak"
        )
        try FileManager.default.copyItem(at: canonical, to: noncanonical)

        let loaded = try await fixture.repository.loadAllRecovery()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.documentID, record.documentID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: noncanonical.path))
    }

    func testWriteSessionRejectsUnsupportedSchema() async throws {
        let fixture = try makeFixture()
        let record = try makeSessionRecord(schemaVersion: 2)

        do {
            try await fixture.repository.writeSession(record)
            XCTFail("Expected unsupported schema failure")
        } catch let error as SessionRepositoryError {
            XCTAssertEqual(error, .unsupportedSchema(expected: 1, actual: 2))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.latestSession.path))
    }

    func testWriteRecoveryRejectsUnsupportedSchema() async throws {
        let fixture = try makeFixture()
        let record = try makeRecoveryRecord(
            schemaVersion: 2,
            documentID: "12345678-90AB-CDEF-1234-567890ABCDEF",
            text: "unsupported"
        )

        do {
            try await fixture.repository.writeRecovery(record)
            XCTFail("Expected unsupported schema failure")
        } catch let error as SessionRepositoryError {
            XCTAssertEqual(error, .unsupportedSchema(expected: 1, actual: 2))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.paths.recovery(documentID: record.documentID).path
            )
        )
    }
}

private extension SessionRepositoryTests {
    struct Fixture {
        let root: URL
        let paths: ApplicationSupportPaths
        let writer: RepositoryWriterSpy
        let repository: SessionRepository
    }

    func makeFixture(quarantineFails: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "session-repository-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let paths = ApplicationSupportPaths(root: root)
        try paths.createDirectories(using: .default)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let writer = RepositoryWriterSpy(quarantineFails: quarantineFails)
        return Fixture(
            root: root,
            paths: paths,
            writer: writer,
            repository: SessionRepository(paths: paths, writer: writer)
        )
    }

    func makeSessionRecord(
        schemaVersion: Int = SessionRepository.schemaVersion
    ) throws -> SessionRecord {
        SessionRecord(
            schemaVersion: schemaVersion,
            documentID: try fixedUUID("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            fileReferenceID: try fixedUUID("11111111-2222-3333-4444-555555555555"),
            displayName: "Prompt.md",
            saveState: .edited,
            hasUnsavedChanges: true,
            selection: TextSelection(location: 7, length: 11),
            scrollOffsetY: 42.5,
            lineEnding: .crlf,
            lastSavedHash: "abc123",
            lastKnownDiskMTime: Date(timeIntervalSince1970: 1_700_000_000),
            windowFrame: CGRect(x: 12, y: 34, width: 800, height: 600),
            didCloseCleanly: false,
            savedAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
    }

    func makeRecoveryRecord(
        schemaVersion: Int = SessionRepository.schemaVersion,
        documentID: String,
        text: String
    ) throws -> RecoveryRecord {
        RecoveryRecord(
            schemaVersion: schemaVersion,
            documentID: try fixedUUID(documentID),
            fileReferenceID: try fixedUUID("ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB"),
            filePathHint: "/Users/example/Prompt.md",
            unsavedText: text,
            baseDiskHash: "def456",
            baseDiskMTime: Date(timeIntervalSince1970: 1_699_999_999),
            lineEnding: .lf,
            selection: TextSelection(location: 3, length: 2),
            scrollOffsetY: 91.25,
            savedAt: Date(timeIntervalSince1970: 1_700_000_456)
        )
    }

    func fixedUUID(_ value: String) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: value))
    }

    func assertSortedJSON(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8), file: file, line: line)
        var searchStart = json.startIndex
        for key in object.keys.sorted() {
            let token = "\"\(key)\":"
            let range = try XCTUnwrap(
                json.range(of: token, range: searchStart..<json.endIndex),
                file: file,
                line: line
            )
            searchStart = range.upperBound
        }
    }

    func schemaVersion(in data: Data) throws -> Int {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["schemaVersion"] as? Int)
    }
}

private actor RepositoryWriterSpy: AtomicFileWriting {
    struct Quarantine: Sendable {
        let source: URL
        let destination: URL
    }

    struct Snapshot: Sendable {
        let quarantines: [Quarantine]
        let removals: [URL]
    }

    enum Failure: Error {
        case quarantine
    }

    private let quarantineFails: Bool
    private var quarantines: [Quarantine] = []
    private var removals: [URL] = []

    init(quarantineFails: Bool) {
        self.quarantineFails = quarantineFails
    }

    func write(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }

    func removeIfPresent(_ url: URL) throws {
        removals.append(url)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func quarantine(_ source: URL, as destination: URL) throws {
        quarantines.append(Quarantine(source: source, destination: destination))
        guard !quarantineFails else { throw Failure.quarantine }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func snapshot() -> Snapshot {
        Snapshot(quarantines: quarantines, removals: removals)
    }
}
