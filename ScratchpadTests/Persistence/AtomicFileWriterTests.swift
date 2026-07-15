import Foundation
import XCTest
@testable import Scratchpad

final class AtomicFileWriterTests: XCTestCase {
    func testCreatesEveryCanonicalApplicationSupportDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "scratchpad-paths-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ApplicationSupportPaths(root: root)

        try paths.createDirectories(using: .default)

        for directory in [
            paths.sessionDirectory,
            paths.recoveryDirectory,
            paths.bookmarksDirectory,
            paths.quarantineDirectory,
            paths.logsDirectory
        ] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
        XCTAssertEqual(paths.latestSession.lastPathComponent, "latest-session.json")
        XCTAssertEqual(paths.bookmarkCollection.lastPathComponent, "bookmarks.json")
        let documentID = try XCTUnwrap(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )
        XCTAssertEqual(
            paths.recovery(documentID: documentID)
                .lastPathComponent,
            "document-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.json"
        )
    }

    func testNewDestinationMovesFlushedTemporaryFileIntoPlace() async throws {
        let fileSystem = RecordingAtomicFileSystem()
        let writer = makeWriter(fileSystem: fileSystem)
        let destination = makeRoot().appending(path: "session/latest-session.json")
        let data = Data("new session".utf8)

        try await writer.write(data, to: destination)

        let snapshot = await fileSystem.snapshot()
        XCTAssertEqual(snapshot.data[destination], data)
        XCTAssertEqual(snapshot.calls.count, 2)
        guard case let .writeAndSynchronize(recordedData, temporaryURL) = snapshot.calls[0] else {
            return XCTFail("Expected a synchronized temporary write first")
        }
        XCTAssertEqual(recordedData, data)
        XCTAssertEqual(temporaryURL.deletingLastPathComponent(), destination.deletingLastPathComponent())
        XCTAssertTrue(temporaryURL.lastPathComponent.hasPrefix(".scratchpad-"))
        XCTAssertTrue(temporaryURL.lastPathComponent.hasSuffix(".tmp"))
        XCTAssertEqual(snapshot.calls[1], .move(temporaryURL, destination))
    }

    func testExistingDestinationUsesAtomicReplacement() async throws {
        let destination = makeRoot().appending(path: "bookmarks/bookmarks.json")
        let original = Data("old bookmarks".utf8)
        let fileSystem = RecordingAtomicFileSystem(initialData: [destination: original])
        let writer = makeWriter(fileSystem: fileSystem)
        let replacement = Data("new bookmarks".utf8)

        try await writer.write(replacement, to: destination)

        let snapshot = await fileSystem.snapshot()
        XCTAssertEqual(snapshot.data[destination], replacement)
        guard case let .writeAndSynchronize(_, temporaryURL) = snapshot.calls.first else {
            return XCTFail("Expected a synchronized temporary write first")
        }
        XCTAssertEqual(snapshot.calls, [
            .writeAndSynchronize(replacement, temporaryURL),
            .replace(destination, temporaryURL)
        ])
    }

    func testReplacementFailureLeavesExistingDestinationUnchanged() async throws {
        let destination = makeRoot().appending(path: "session/latest-session.json")
        let original = Data("retained session".utf8)
        let fileSystem = RecordingAtomicFileSystem(
            initialData: [destination: original],
            failure: .replace
        )
        let writer = makeWriter(fileSystem: fileSystem)

        await XCTAssertThrowsErrorAsync {
            try await writer.write(Data("lost candidate".utf8), to: destination)
        } verify: { error in
            XCTAssertTrue(error is AtomicFileWriterError)
        }

        let snapshot = await fileSystem.snapshot()
        XCTAssertEqual(snapshot.data[destination], original)
    }

    func testFailureRemovesOnlyTheTemporaryFile() async throws {
        let destination = makeRoot().appending(path: "session/latest-session.json")
        let fileSystem = RecordingAtomicFileSystem(
            initialData: [destination: Data("keep me".utf8)],
            failure: .replace
        )
        let writer = makeWriter(fileSystem: fileSystem)

        await XCTAssertThrowsErrorAsync {
            try await writer.write(Data("candidate".utf8), to: destination)
        }

        let snapshot = await fileSystem.snapshot()
        let removedURLs = snapshot.calls.compactMap { call -> URL? in
            guard case let .remove(url) = call else { return nil }
            return url
        }
        XCTAssertEqual(removedURLs.count, 1)
        XCTAssertTrue(removedURLs[0].lastPathComponent.hasPrefix(".scratchpad-"))
        XCTAssertTrue(removedURLs[0].lastPathComponent.hasSuffix(".tmp"))
        XCTAssertNotEqual(removedURLs[0], destination)
        XCTAssertEqual(snapshot.data[destination], Data("keep me".utf8))
    }

    func testRemoveIfPresentIsIdempotent() async throws {
        let url = makeRoot().appending(path: "recovery/document.json")
        let fileSystem = RecordingAtomicFileSystem(initialData: [url: Data("recovery".utf8)])
        let writer = makeWriter(fileSystem: fileSystem)

        try await writer.removeIfPresent(url)
        try await writer.removeIfPresent(url)

        let snapshot = await fileSystem.snapshot()
        XCTAssertNil(snapshot.data[url])
        XCTAssertEqual(snapshot.calls, [.remove(url)])
    }

    func testQuarantineMovesWithinApplicationSupportVolume() async throws {
        let root = makeRoot()
        let paths = ApplicationSupportPaths(root: root)
        let source = paths.recoveryDirectory.appending(path: "bad.json")
        let destination = paths.quarantine(originalName: "bad.json", at: Date(timeIntervalSince1970: 0))
        let bytes = Data("corrupt".utf8)
        let fileSystem = RecordingAtomicFileSystem(initialData: [source: bytes])
        let writer = makeWriter(fileSystem: fileSystem, root: root)

        try await writer.quarantine(source, as: destination)

        let snapshot = await fileSystem.snapshot()
        XCTAssertNil(snapshot.data[source])
        XCTAssertEqual(snapshot.data[destination], bytes)
        XCTAssertEqual(snapshot.calls, [.move(source, destination)])
    }

    func testQuarantineFailureLeavesOriginalUntouched() async throws {
        let root = makeRoot()
        let paths = ApplicationSupportPaths(root: root)
        let source = paths.bookmarkCollection
        let destination = paths.quarantine(originalName: "bookmarks.json", at: Date(timeIntervalSince1970: 0))
        let original = Data("invalid bookmarks".utf8)
        let fileSystem = RecordingAtomicFileSystem(
            initialData: [source: original],
            failure: .move
        )
        let writer = makeWriter(fileSystem: fileSystem, root: root)

        await XCTAssertThrowsErrorAsync {
            try await writer.quarantine(source, as: destination)
        } verify: { error in
            XCTAssertTrue(error is AtomicFileWriterError)
        }

        let snapshot = await fileSystem.snapshot()
        XCTAssertEqual(snapshot.data[source], original)
        XCTAssertNil(snapshot.data[destination])
        XCTAssertFalse(snapshot.calls.contains { call in
            if case .remove = call { return true }
            return false
        })
    }

    func testQuarantineRejectsOutOfRootPathsBeforeMutation() async {
        let root = makeRoot()
        let paths = ApplicationSupportPaths(root: root)
        let insideSource = paths.recoveryDirectory.appending(path: "bad.json")
        let insideDestination = paths.quarantineDirectory.appending(path: "bad.json")
        let outsideSource = makeRoot().appending(path: "bad.json")
        let outsideDestination = makeRoot().appending(path: "quarantine/bad.json")
        let fileSystem = RecordingAtomicFileSystem(
            initialData: [insideSource: Data("inside".utf8), outsideSource: Data("outside".utf8)]
        )
        let writer = makeWriter(fileSystem: fileSystem, root: root)

        await XCTAssertThrowsErrorAsync {
            try await writer.quarantine(outsideSource, as: insideDestination)
        } verify: { error in
            XCTAssertEqual(
                error as? AtomicFileWriterError,
                .invalidQuarantineLocation(source: outsideSource, destination: insideDestination)
            )
        }
        await XCTAssertThrowsErrorAsync {
            try await writer.quarantine(insideSource, as: outsideDestination)
        } verify: { error in
            XCTAssertEqual(
                error as? AtomicFileWriterError,
                .invalidQuarantineLocation(source: insideSource, destination: outsideDestination)
            )
        }

        let snapshot = await fileSystem.snapshot()
        XCTAssertTrue(snapshot.calls.isEmpty)
    }

    func testQuarantineRejectsSymlinkEscapeBeforeMutation() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "scratchpad-root-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let outside = fileManager.temporaryDirectory.appending(
            path: "scratchpad-outside-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outside)
        }
        let paths = ApplicationSupportPaths(root: root)
        try fileManager.createDirectory(at: paths.quarantineDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: paths.recoveryDirectory,
            withDestinationURL: outside
        )
        let source = paths.recoveryDirectory.appending(path: "bad.json")
        let destination = paths.quarantineDirectory.appending(path: "bad.json")
        let bytes = Data("escape".utf8)
        try bytes.write(to: outside.appending(path: "bad.json"))
        let fileSystem = RecordingAtomicFileSystem(initialData: [source: bytes])
        let writer = makeWriter(fileSystem: fileSystem, root: root)

        await XCTAssertThrowsErrorAsync {
            try await writer.quarantine(source, as: destination)
        } verify: { error in
            XCTAssertEqual(
                error as? AtomicFileWriterError,
                .invalidQuarantineLocation(source: source, destination: destination)
            )
        }

        let snapshot = await fileSystem.snapshot()
        XCTAssertTrue(snapshot.calls.isEmpty)
    }

    func testConcurrentWritesToSameDestinationAreSerialized() async {
        let root = makeRoot()
        let destination = root.appending(path: "session/latest-session.json")
        let payloads = (0..<32).map { Data("complete-payload-\($0)".utf8) }
        let fileSystem = RecordingAtomicFileSystem()
        let writer = makeWriter(fileSystem: fileSystem, root: root)

        let allSucceeded = await withTaskGroup(of: Bool.self) { group in
            for payload in payloads {
                group.addTask {
                    do {
                        try await writer.write(payload, to: destination)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var succeeded = true
            for await result in group {
                succeeded = succeeded && result
            }
            return succeeded
        }

        let snapshot = await fileSystem.snapshot()
        XCTAssertTrue(allSucceeded)
        XCTAssertFalse(snapshot.overlapDetected)
        XCTAssertTrue(payloads.contains(snapshot.data[destination] ?? Data()))
    }

    func testLiveFileSystemWritesNewAndReplacesExistingDestination() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "scratchpad-live-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        let paths = ApplicationSupportPaths(root: root)
        try paths.createDirectories(using: fileManager)
        let writer = AtomicFileWriter(fileSystem: LiveAtomicFileSystem(), paths: paths)
        let destination = paths.latestSession
        let original = Data("original".utf8)
        let replacement = Data("replacement".utf8)

        try await writer.write(original, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), original)

        try await writer.write(replacement, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), replacement)
        XCTAssertFalse(
            try fileManager.contentsOfDirectory(atPath: paths.sessionDirectory.path)
                .contains { $0.hasPrefix(".scratchpad-") }
        )
    }

    func testLiveFileSystemRemovesSynchronizedTemporaryFileDuringCleanup() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "scratchpad-live-cleanup-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let temporaryURL = root.appending(path: ".scratchpad-cleanup.tmp")
        let fileSystem = LiveAtomicFileSystem()

        try await fileSystem.writeAndSynchronize(Data("temporary".utf8), to: temporaryURL)
        XCTAssertTrue(fileManager.fileExists(atPath: temporaryURL.path))

        try await fileSystem.remove(temporaryURL)
        XCTAssertFalse(fileManager.fileExists(atPath: temporaryURL.path))
    }

    func testContentHashMatchesKnownSHA256Vector() {
        XCTAssertEqual(
            ContentHash.sha256(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testQuarantineSourceCannotInterleaveWithConcurrentRemoval() async {
        let root = makeRoot()
        let paths = ApplicationSupportPaths(root: root)
        let source = paths.recoveryDirectory.appending(path: "bad.json")
        let destination = paths.quarantineDirectory.appending(path: "bad.json")
        let writer = makeWriter(fileSystem: RecordingAtomicFileSystem(), root: root)

        let quarantineKeys = await writer.transactionKeysForQuarantine(
            source: source,
            destination: destination
        )
        let removalKey = await writer.transactionKey(for: source)

        XCTAssertEqual(quarantineKeys, [source, destination].sorted { $0.path < $1.path })
        XCTAssertTrue(quarantineKeys.contains(removalKey))
    }

    private func makeWriter(
        fileSystem: any AtomicFileSystem,
        root: URL? = nil
    ) -> AtomicFileWriter {
        AtomicFileWriter(
            fileSystem: fileSystem,
            paths: ApplicationSupportPaths(root: root ?? makeRoot())
        )
    }

    private func makeRoot() -> URL {
        URL(fileURLWithPath: "/tmp/scratchpad-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum RecordingFailure: Error, Sendable {
    case replace
    case move
}

private enum AtomicFileSystemCall: Equatable, Sendable {
    case writeAndSynchronize(Data, URL)
    case replace(URL, URL)
    case move(URL, URL)
    case remove(URL)
}

private struct AtomicFileSystemSnapshot: Sendable {
    let data: [URL: Data]
    let calls: [AtomicFileSystemCall]
    let overlapDetected: Bool
}

private actor RecordingAtomicFileSystem: AtomicFileSystem {
    private var data: [URL: Data]
    private var calls: [AtomicFileSystemCall] = []
    private var pendingTemporaryURLs: Set<URL> = []
    private var overlapDetected = false
    private let failure: RecordingFailure?

    init(initialData: [URL: Data] = [:], failure: RecordingFailure? = nil) {
        data = initialData
        self.failure = failure
    }

    func exists(_ url: URL) -> Bool {
        data[url] != nil
    }

    func writeAndSynchronize(_ newData: Data, to temporaryURL: URL) throws {
        calls.append(.writeAndSynchronize(newData, temporaryURL))
        if !pendingTemporaryURLs.isEmpty {
            overlapDetected = true
        }
        pendingTemporaryURLs.insert(temporaryURL)
        data[temporaryURL] = newData
    }

    func replace(_ destination: URL, with temporaryURL: URL) throws {
        calls.append(.replace(destination, temporaryURL))
        if failure == .replace {
            throw RecordingFailure.replace
        }
        pendingTemporaryURLs.remove(temporaryURL)
        data[destination] = data.removeValue(forKey: temporaryURL)
    }

    func move(_ source: URL, to destination: URL) throws {
        calls.append(.move(source, destination))
        if failure == .move {
            throw RecordingFailure.move
        }
        guard let sourceData = data.removeValue(forKey: source) else {
            throw CocoaError(.fileNoSuchFile)
        }
        pendingTemporaryURLs.remove(source)
        data[destination] = sourceData
    }

    func remove(_ url: URL) throws {
        calls.append(.remove(url))
        pendingTemporaryURLs.remove(url)
        data.removeValue(forKey: url)
    }

    func snapshot() -> AtomicFileSystemSnapshot {
        AtomicFileSystemSnapshot(
            data: data,
            calls: calls,
            overlapDetected: overlapDetected
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    verify: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}
