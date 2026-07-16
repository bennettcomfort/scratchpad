import Foundation
import XCTest
@testable import Scratchpad

final class FileServiceTests: XCTestCase {
    func testOpenRejectsInvalidUTF8WithoutAdoptingFile() async throws {
        let fixture = await makeFixture(data: Data([0xC3, 0x28]))

        await XCTAssertFileServiceThrows {
            _ = try await fixture.service.open(fixture.reference)
        } verify: { error in
            XCTAssertEqual(error as? FileServiceError, .invalidUTF8)
        }

        let writes = await fixture.writer.writes()
        let accessCounts = await fixture.bookmarks.accessCounts()
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(accessCounts, .init(begun: 1, ended: 1))
    }

    func testOpenNormalizesCRLFAndRetainsCRLFMetadata() async throws {
        let bytes = Data("one\r\ntwo\rthree\n".utf8)
        let fixture = await makeFixture(data: bytes)

        let result = try await fixture.service.open(fixture.reference)

        XCTAssertEqual(result.reference, fixture.reference)
        XCTAssertEqual(result.text, "one\ntwo\nthree\n")
        XCTAssertEqual(result.displayName, fixture.url.lastPathComponent)
        XCTAssertEqual(result.lineEnding, .crlf)
        XCTAssertEqual(result.contentHash, ContentHash.sha256(bytes))
        XCTAssertEqual(result.modificationDate, fixture.mtime)
    }

    func testOpenUsesLFForAnEmptyFile() async throws {
        let fixture = await makeFixture(data: Data())

        let result = try await fixture.service.open(fixture.reference)

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(result.lineEnding, .lf)
        XCTAssertEqual(result.contentHash, ContentHash.sha256(Data()))
    }

    func testInspectDistinguishesUnchangedChangedMissingAndReadOnly() async throws {
        let fixture = await makeFixture(data: Data("base".utf8))
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(Data("base".utf8)),
            mtime: fixture.mtime
        )
        let unchanged = try await fixture.service.inspect(snapshot)
        XCTAssertEqual(unchanged, .unchanged)

        let changedDate = fixture.mtime.addingTimeInterval(10)
        let changedData = Data("changed".utf8)
        await fixture.fileSystem.set(
            fixture.url,
            data: changedData,
            modificationDate: changedDate,
            isWritable: true
        )
        let changed = try await fixture.service.inspect(snapshot)
        XCTAssertEqual(
            changed,
            .changed(
                contentHash: ContentHash.sha256(changedData),
                modificationDate: changedDate
            )
        )

        await fixture.fileSystem.remove(fixture.url)
        let missing = try await fixture.service.inspect(snapshot)
        XCTAssertEqual(missing, .missing)

        await fixture.fileSystem.set(
            fixture.url,
            data: changedData,
            modificationDate: changedDate,
            isWritable: false
        )
        let readOnly = try await fixture.service.inspect(snapshot)
        XCTAssertEqual(readOnly, .readOnly)
    }

    func testSaveRejectsHashOrMTimeMismatchBeforeWriting() async throws {
        let base = Data("base".utf8)
        let fixture = await makeFixture(data: base)
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "replacement"
        )

        let hashMismatch = Data("other".utf8)
        await fixture.fileSystem.set(
            fixture.url,
            data: hashMismatch,
            modificationDate: fixture.mtime,
            isWritable: true
        )
        await assertConflict(service: fixture.service, snapshot: snapshot)

        await fixture.fileSystem.set(
            fixture.url,
            data: base,
            modificationDate: fixture.mtime.addingTimeInterval(1),
            isWritable: true
        )
        await assertConflict(service: fixture.service, snapshot: snapshot)

        let writes = await fixture.writer.writes()
        XCTAssertTrue(writes.isEmpty)

        let concurrentFixture = await makeFixture(data: base, blockFirstWrite: true)
        let concurrentSnapshot = makeSnapshot(
            reference: concurrentFixture.reference,
            hash: ContentHash.sha256(base),
            mtime: concurrentFixture.mtime,
            text: "serialized"
        )
        let firstSave = Task {
            await saveOutcome(
                service: concurrentFixture.service,
                snapshot: concurrentSnapshot
            )
        }
        await concurrentFixture.writer.waitUntilFirstWriteStarts()
        let secondSave = Task {
            await saveOutcome(
                service: concurrentFixture.service,
                snapshot: concurrentSnapshot
            )
        }
        await Task.yield()
        await concurrentFixture.writer.releaseFirstWrite()

        let outcomes = [await firstSave.value, await secondSave.value]
        let concurrentWriteCount = await concurrentFixture.writer.writeCount()
        XCTAssertEqual(outcomes.filter(\.isSuccess).count, 1)
        XCTAssertEqual(outcomes.filter(\.isConflict).count, 1)
        XCTAssertEqual(concurrentWriteCount, 1)
    }

    func testSavePreservesStoredCRLFConvention() async throws {
        let base = Data("old\r\ntext".utf8)
        let fixture = await makeFixture(data: base)
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "new\ntext\n",
            lineEnding: .crlf
        )

        let result = try await fixture.service.save(snapshot)

        let expected = Data("new\r\ntext\r\n".utf8)
        let savedData = await fixture.fileSystem.data(at: fixture.url)
        XCTAssertEqual(savedData, expected)
        XCTAssertEqual(result.lineEnding, .crlf)
        XCTAssertEqual(result.contentHash, ContentHash.sha256(expected))
        let acquiredTokenID = await fixture.bookmarks.acquiredTokenID()
        let refreshedTokenIDs = await fixture.bookmarks.refreshedTokenIDs()
        XCTAssertEqual(refreshedTokenIDs, [acquiredTokenID].compactMap { $0 })
    }

    func testSaveAsWritesSelectedDestinationWithoutPathFallback() async throws {
        let fixture = await makeFixture(data: Data("old".utf8))
        let misleadingReference = ExternalFileReference(
            bookmarkID: fixture.reference.bookmarkID,
            pathHint: "/tmp/path-hint-must-not-be-used.md"
        )
        let snapshot = makeSnapshot(reference: nil, hash: nil, mtime: nil, text: "selected")

        let result = try await fixture.service.saveAs(snapshot, to: misleadingReference)

        let destinations = await fixture.writer.writes().map(\.destination)
        let savedData = await fixture.fileSystem.data(at: fixture.url)
        XCTAssertEqual(destinations, [fixture.url])
        XCTAssertEqual(savedData, Data("selected".utf8))
        XCTAssertEqual(result.reference, misleadingReference)
        XCTAssertEqual(result.displayName, fixture.url.lastPathComponent)
        let acquiredTokenID = await fixture.bookmarks.acquiredTokenID()
        let refreshedTokenIDs = await fixture.bookmarks.refreshedTokenIDs()
        XCTAssertEqual(refreshedTokenIDs, [acquiredTokenID].compactMap { $0 })
    }

    func testSaveAsSelectedURLWritesBeforeCreatingBookmark() async throws {
        let events = SelectedURLEventRecorder()
        let fileSystem = SelectedURLFileSystemSpy(events: events)
        let writer = SelectedURLWriterSpy(fileSystem: fileSystem, events: events)
        let bookmarks = SelectedURLBookmarkSpy(events: events)
        let service = FileService(
            bookmarks: bookmarks,
            writer: writer,
            fileSystem: fileSystem
        )
        let destination = URL(fileURLWithPath: "/panel/New.md")
        let snapshot = makeSnapshot(
            reference: nil,
            hash: nil,
            mtime: nil,
            text: "selected destination"
        )

        let result = try await service.saveAs(snapshot, toSelectedURL: destination)

        let recordedEvents = await events.snapshot()
        XCTAssertEqual(recordedEvents, ["write", "verify", "bookmark"])
        XCTAssertEqual(result.reference.pathHint, destination.path)
        XCTAssertEqual(result.contentHash, ContentHash.sha256(snapshot.persistedBytes))
    }

    func testSaveAsSelectedURLBookmarkFailureLeavesVerifiedBytesButReturnsFailure() async {
        let events = SelectedURLEventRecorder()
        let fileSystem = SelectedURLFileSystemSpy(events: events)
        let writer = SelectedURLWriterSpy(fileSystem: fileSystem, events: events)
        let bookmarks = SelectedURLBookmarkSpy(events: events, storeFails: true)
        let service = FileService(
            bookmarks: bookmarks,
            writer: writer,
            fileSystem: fileSystem
        )
        let destination = URL(fileURLWithPath: "/panel/BookmarkFailure.md")
        let snapshot = makeSnapshot(
            reference: nil,
            hash: nil,
            mtime: nil,
            text: "verified before bookmark"
        )

        await XCTAssertFileServiceThrows(.accessFailed) {
            _ = try await service.saveAs(snapshot, toSelectedURL: destination)
        }

        let recordedEvents = await events.snapshot()
        let verifiedBytes = await fileSystem.bytes(at: destination)
        XCTAssertEqual(recordedEvents, ["write", "verify", "bookmark"])
        XCTAssertEqual(verifiedBytes, snapshot.persistedBytes)
    }

    func testSaveVerificationFailureThrowsAfterRereadMismatch() async throws {
        let base = Data("base".utf8)
        let fixture = await makeFixture(
            data: base,
            verificationReplacement: Data("wrong".utf8)
        )
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "wanted"
        )
        var returnedResult: FileSaveResult?

        do {
            returnedResult = try await fixture.service.save(snapshot)
            XCTFail("Expected verification failure")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .verificationFailed)
        }

        XCTAssertNil(returnedResult)
        let accessCounts = await fixture.bookmarks.accessCounts()
        XCTAssertEqual(accessCounts, .init(begun: 1, ended: 1))
    }

    func testEveryExitPathEndsScopedAccessExactlyOnce() async throws {
        for exitPath in ExitPathCase.allCases {
            let tokenID = UUID()
            let fixture = await makeFixture(
                data: Data("base".utf8),
                tokenID: tokenID
            )

            await exercise(exitPath, fixture: fixture)

            let access = await fixture.bookmarks.accessSnapshot()
            XCTAssertEqual(access.acquired, [tokenID], "\(exitPath)")
            XCTAssertEqual(access.ended, [tokenID], "\(exitPath)")
            XCTAssertEqual(Set(access.ended).count, access.ended.count, "\(exitPath)")
        }
    }

    func testSuccessfulSaveReturnsVerifiedHashMTimeAndReference() async throws {
        let base = Data("base".utf8)
        let fixture = await makeFixture(data: base)
        let documentID = UUID()
        let snapshot = makeSnapshot(
            documentID: documentID,
            generation: 42,
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "saved"
        )

        let result = try await fixture.service.save(snapshot)

        let written = Data("saved".utf8)
        XCTAssertEqual(result.documentID, documentID)
        XCTAssertEqual(result.initiatingGeneration, 42)
        XCTAssertEqual(result.reference, fixture.reference)
        XCTAssertEqual(result.displayName, fixture.url.lastPathComponent)
        XCTAssertEqual(result.lineEnding, .lf)
        XCTAssertEqual(result.contentHash, ContentHash.sha256(written))
        XCTAssertEqual(result.modificationDate, fixture.mtime.addingTimeInterval(1))
    }

    func testSaveRejectsMutationAfterPreflightBeforeReplacement() async throws {
        let base = Data("base A".utf8)
        let fixture = await makeFixture(data: base)
        let versionB = AtomicFileVersion(
            contentHash: ContentHash.sha256(Data("external B".utf8)),
            modificationDate: fixture.mtime.addingTimeInterval(5)
        )
        await fixture.writer.setConditionalBehavior(.result(.conflict(versionB)))
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "candidate C"
        )
        var result: FileSaveResult?

        do {
            result = try await fixture.service.save(snapshot)
            XCTFail("Expected a late conflict")
        } catch let error as FileServiceError {
            XCTAssertEqual(
                error,
                .conflict(
                    contentHash: versionB.contentHash,
                    modificationDate: versionB.modificationDate
                )
            )
        }

        let unconditionalWrites = await fixture.writer.writes()
        let conditionalWriteCount = await fixture.writer.conditionalWriteCount()
        XCTAssertNil(result)
        XCTAssertTrue(unconditionalWrites.isEmpty)
        XCTAssertEqual(conditionalWriteCount, 1)
        let access = await fixture.bookmarks.accessSnapshot()
        XCTAssertEqual(access.acquired, access.ended)
        XCTAssertEqual(access.acquired.count, 1)
        XCTAssertEqual(Set(access.ended).count, 1)
    }

    func testSaveMapsUnknownConditionalWriterErrorToWriteFailure() async throws {
        let base = Data("base".utf8)
        let tokenID = UUID()
        let fixture = await makeFixture(data: base, tokenID: tokenID)
        await fixture.writer.setConditionalBehavior(.unknownFailure)
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "candidate"
        )
        var result: FileSaveResult?

        do {
            result = try await fixture.service.save(snapshot)
            XCTFail("Expected the conditional writer error to fail Save")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .writeFailed)
        }

        let conditionalWriteCount = await fixture.writer.conditionalWriteCount()
        let unconditionalWrites = await fixture.writer.writes()
        XCTAssertNil(result)
        XCTAssertEqual(conditionalWriteCount, 1)
        XCTAssertTrue(unconditionalWrites.isEmpty)
        let access = await fixture.bookmarks.accessSnapshot()
        XCTAssertEqual(access.acquired, [tokenID])
        XCTAssertEqual(access.ended, [tokenID])
    }

    func testLiveFileSystemReadsBytesModificationDateAndWritability() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "scratchpad-live-file-service-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "document.md")
        let bytes = Data("live bytes".utf8)
        try bytes.write(to: url)
        let firstDate = Date(timeIntervalSince1970: 1_000)
        try fileManager.setAttributes(
            [.modificationDate: firstDate],
            ofItemAtPath: url.path
        )

        let fileSystem = LiveFileSystemAccess()
        let result = try await fileSystem.read(url)

        XCTAssertEqual(result.data, bytes)
        XCTAssertEqual(result.modificationDate, firstDate)
        XCTAssertTrue(result.isWritable)

        let secondDate = Date(timeIntervalSince1970: 2_000)
        try fileManager.setAttributes(
            [.modificationDate: secondDate],
            ofItemAtPath: url.path
        )
        let refreshed = try await fileSystem.read(url)
        XCTAssertEqual(refreshed.modificationDate, secondDate)
    }

    func testLiveFileSystemMapsMissingAndNonRegularFiles() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "scratchpad-live-file-errors-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let missing = root.appending(path: "missing.md")

        await XCTAssertFileSystemThrows(.missing) {
            _ = try await LiveFileSystemAccess().read(missing)
        }
        await XCTAssertFileSystemThrows(.readFailed) {
            _ = try await LiveFileSystemAccess().read(root)
        }
    }

    private func assertConflict(service: FileService, snapshot: DocumentSnapshot) async {
        await XCTAssertFileServiceThrows {
            _ = try await service.save(snapshot)
        } verify: { error in
            guard case .conflict = error as? FileServiceError else {
                return XCTFail("Expected conflict, got \(error)")
            }
        }
    }

    private func exercise(
        _ exitPath: ExitPathCase,
        fixture: FileServiceFixture
    ) async {
        let base = Data("base".utf8)
        let snapshot = makeSnapshot(
            reference: fixture.reference,
            hash: ContentHash.sha256(base),
            mtime: fixture.mtime,
            text: "saved"
        )
        let changedData = Data("changed".utf8)
        let changedDate = fixture.mtime.addingTimeInterval(10)

        switch exitPath {
        case .openSuccess:
            _ = try? await fixture.service.open(fixture.reference)
        case .openInvalidUTF8:
            await fixture.fileSystem.set(
                fixture.url,
                data: Data([0xFF]),
                modificationDate: fixture.mtime,
                isWritable: true
            )
            await XCTAssertFileServiceThrows(.invalidUTF8) {
                _ = try await fixture.service.open(fixture.reference)
            }
        case .openMissing:
            await fixture.fileSystem.remove(fixture.url)
            await XCTAssertFileServiceThrows(.missing) {
                _ = try await fixture.service.open(fixture.reference)
            }
        case .openReadFailure:
            await fixture.fileSystem.enqueue(.failure, for: fixture.url)
            await XCTAssertFileServiceThrows(.readFailed) {
                _ = try await fixture.service.open(fixture.reference)
            }
        case .inspectUnchanged:
            let status = try? await fixture.service.inspect(snapshot)
            XCTAssertEqual(status, .unchanged)
        case .inspectChanged:
            await fixture.fileSystem.set(
                fixture.url,
                data: changedData,
                modificationDate: changedDate,
                isWritable: true
            )
            let status = try? await fixture.service.inspect(snapshot)
            XCTAssertEqual(
                status,
                .changed(
                    contentHash: ContentHash.sha256(changedData),
                    modificationDate: changedDate
                )
            )
        case .inspectMissing:
            await fixture.fileSystem.remove(fixture.url)
            let status = try? await fixture.service.inspect(snapshot)
            XCTAssertEqual(status, .missing)
        case .inspectReadOnly:
            await fixture.fileSystem.set(
                fixture.url,
                data: base,
                modificationDate: fixture.mtime,
                isWritable: false
            )
            let status = try? await fixture.service.inspect(snapshot)
            XCTAssertEqual(status, .readOnly)
        case .saveSuccess:
            _ = try? await fixture.service.save(snapshot)
        case .saveEarlyConflict:
            await fixture.fileSystem.set(
                fixture.url,
                data: changedData,
                modificationDate: changedDate,
                isWritable: true
            )
            await XCTAssertFileServiceThrowsConflict {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveLateConflict:
            await fixture.writer.setConditionalBehavior(
                .result(
                    .conflict(
                        AtomicFileVersion(
                            contentHash: ContentHash.sha256(changedData),
                            modificationDate: changedDate
                        )
                    )
                )
            )
            await XCTAssertFileServiceThrowsConflict {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveReadOnly:
            await fixture.writer.setConditionalBehavior(.result(.readOnly))
            await XCTAssertFileServiceThrows(.readOnly) {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveWriteFailure:
            await fixture.writer.setConditionalBehavior(.writeFailure)
            await XCTAssertFileServiceThrows(.writeFailed) {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveReadBackMissing:
            await fixture.writer.setConditionalBehavior(.result(.missing))
            await XCTAssertFileServiceThrows(.missing) {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveReadBackFailure:
            await fixture.writer.setConditionalBehavior(.readFailure)
            await XCTAssertFileServiceThrows(.readFailed) {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveByteMismatch:
            await fixture.writer.setConditionalBehavior(.verificationFailure)
            await XCTAssertFileServiceThrows(.verificationFailed) {
                _ = try await fixture.service.save(snapshot)
            }
        case .saveAsNew:
            await fixture.fileSystem.remove(fixture.url)
            _ = try? await fixture.service.saveAs(snapshot, to: fixture.reference)
        case .saveAsExisting:
            _ = try? await fixture.service.saveAs(snapshot, to: fixture.reference)
        case .saveAsReadOnly:
            await fixture.fileSystem.set(
                fixture.url,
                data: base,
                modificationDate: fixture.mtime,
                isWritable: false
            )
            await XCTAssertFileServiceThrows(.readOnly) {
                _ = try await fixture.service.saveAs(snapshot, to: fixture.reference)
            }
        case .saveAsWriteFailure:
            await fixture.writer.setUnconditionalWriteFailure()
            await XCTAssertFileServiceThrows(.writeFailed) {
                _ = try await fixture.service.saveAs(snapshot, to: fixture.reference)
            }
        case .saveAsReadBackMissing:
            await fixture.fileSystem.enqueue(
                .snapshot(
                    FileReadSnapshot(
                        data: base,
                        modificationDate: fixture.mtime,
                        isWritable: true
                    )
                ),
                for: fixture.url
            )
            await fixture.fileSystem.enqueue(.missing, for: fixture.url)
            await XCTAssertFileServiceThrows(.missing) {
                _ = try await fixture.service.saveAs(snapshot, to: fixture.reference)
            }
        case .saveAsReadBackFailure:
            await fixture.fileSystem.enqueue(
                .snapshot(
                    FileReadSnapshot(
                        data: base,
                        modificationDate: fixture.mtime,
                        isWritable: true
                    )
                ),
                for: fixture.url
            )
            await fixture.fileSystem.enqueue(.failure, for: fixture.url)
            await XCTAssertFileServiceThrows(.readFailed) {
                _ = try await fixture.service.saveAs(snapshot, to: fixture.reference)
            }
        case .saveAsByteMismatch:
            await fixture.writer.setVerificationReplacement(Data("wrong".utf8))
            await XCTAssertFileServiceThrows(.verificationFailed) {
                _ = try await fixture.service.saveAs(snapshot, to: fixture.reference)
            }
        }
    }

}

private enum ExitPathCase: String, CaseIterable, Sendable {
    case openSuccess
    case openInvalidUTF8
    case openMissing
    case openReadFailure
    case inspectUnchanged
    case inspectChanged
    case inspectMissing
    case inspectReadOnly
    case saveSuccess
    case saveEarlyConflict
    case saveLateConflict
    case saveReadOnly
    case saveWriteFailure
    case saveReadBackMissing
    case saveReadBackFailure
    case saveByteMismatch
    case saveAsNew
    case saveAsExisting
    case saveAsReadOnly
    case saveAsWriteFailure
    case saveAsReadBackMissing
    case saveAsReadBackFailure
    case saveAsByteMismatch
}

private enum SaveOutcome: Sendable {
    case success
    case failure(FileServiceError)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isConflict: Bool {
        if case .failure(.conflict) = self { return true }
        return false
    }
}

private func saveOutcome(
    service: FileService,
    snapshot: DocumentSnapshot
) async -> SaveOutcome {
    do {
        _ = try await service.save(snapshot)
        return .success
    } catch let error as FileServiceError {
        return .failure(error)
    } catch {
        return .failure(.writeFailed)
    }
}

private func XCTAssertFileServiceThrows(
    _ expression: () async throws -> Void,
    verify: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify(error)
    }
}

private func XCTAssertFileServiceThrows(
    _ expected: FileServiceError,
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    await XCTAssertFileServiceThrows(expression, verify: { error in
        XCTAssertEqual(error as? FileServiceError, expected, file: file, line: line)
    }, file: file, line: line)
}

private func XCTAssertFileServiceThrowsConflict(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    await XCTAssertFileServiceThrows(expression, verify: { error in
        guard case .conflict = error as? FileServiceError else {
            return XCTFail("Expected conflict, got \(error)", file: file, line: line)
        }
    }, file: file, line: line)
}

private func XCTAssertFileSystemThrows(
    _ expected: FileSystemAccessError,
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? FileSystemAccessError, expected, file: file, line: line)
    }
}

private struct FileServiceFixture {
    let service: FileService
    let bookmarks: FileServiceBookmarkSpy
    let writer: FileServiceWriterSpy
    let fileSystem: FileServiceFileSystemSpy
    let reference: ExternalFileReference
    let url: URL
    let mtime: Date
}

private func makeFixture(
    data: Data,
    isWritable: Bool = true,
    verificationReplacement: Data? = nil,
    blockFirstWrite: Bool = false,
    tokenID: UUID = UUID()
) async -> FileServiceFixture {
    let url = URL(filePath: "/resolved/Selected.md")
    let mtime = Date(timeIntervalSince1970: 1_000)
    let reference = ExternalFileReference(bookmarkID: UUID(), pathHint: "/wrong/Hint.md")
    let fileSystem = FileServiceFileSystemSpy()
    let bookmarks = FileServiceBookmarkSpy(url: url, tokenIDs: [tokenID])
    let writer = FileServiceWriterSpy(
        fileSystem: fileSystem,
        verificationReplacement: verificationReplacement,
        blockFirstWrite: blockFirstWrite
    )
    await fileSystem.set(
        url,
        data: data,
        modificationDate: mtime,
        isWritable: isWritable
    )
    return FileServiceFixture(
        service: FileService(bookmarks: bookmarks, writer: writer, fileSystem: fileSystem),
        bookmarks: bookmarks,
        writer: writer,
        fileSystem: fileSystem,
        reference: reference,
        url: url,
        mtime: mtime
    )
}

private func makeSnapshot(
    documentID: UUID = UUID(),
    generation: Int = 1,
    reference: ExternalFileReference?,
    hash: String?,
    mtime: Date?,
    text: String = "base",
    lineEnding: LineEnding = .lf
) -> DocumentSnapshot {
    DocumentSnapshot(
        documentID: documentID,
        generation: generation,
        text: text,
        fileReference: reference,
        saveState: reference == nil ? .untitled : .edited,
        hasUnsavedChanges: true,
        selection: TextSelection(location: 0, length: 0),
        scrollOffsetY: 0,
        lineEnding: lineEnding,
        lastSavedHash: hash,
        lastKnownDiskMTime: mtime
    )
}

private actor FileServiceBookmarkSpy: BookmarkAccessing {
    struct AccessCounts: Equatable {
        let begun: Int
        let ended: Int
    }

    private let url: URL
    private var begun = 0
    private var ended = 0
    private var tokenIDs: [UUID]
    private var acquiredTokenIDs: [UUID] = []
    private var endedTokenIDs: [UUID] = []
    private var refreshedTokenIDsStorage: [UUID] = []
    private var nextBeginError: Error?

    init(url: URL, tokenIDs: [UUID]) {
        self.url = url
        self.tokenIDs = tokenIDs
    }

    func storeSelection(_ url: URL) async throws -> ExternalFileReference {
        ExternalFileReference(bookmarkID: UUID(), pathHint: url.path)
    }

    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference? { nil }

    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken {
        if let nextBeginError {
            self.nextBeginError = nil
            throw nextBeginError
        }
        begun += 1
        let tokenID = tokenIDs.isEmpty ? UUID() : tokenIDs.removeFirst()
        acquiredTokenIDs.append(tokenID)
        return ScopedAccessToken(id: tokenID, url: url)
    }

    func endAccess(_ token: ScopedAccessToken) async {
        ended += 1
        endedTokenIDs.append(token.id)
    }

    func refresh(_ token: ScopedAccessToken) async throws {
        refreshedTokenIDsStorage.append(token.id)
    }
    func forget(_ reference: ExternalFileReference) async throws {}

    func failNextBegin(with error: Error) {
        nextBeginError = error
    }

    func accessCounts() -> AccessCounts {
        AccessCounts(begun: begun, ended: ended)
    }

    func accessSnapshot() -> (acquired: [UUID], ended: [UUID]) {
        (acquiredTokenIDs, endedTokenIDs)
    }

    func acquiredTokenID() -> UUID? {
        acquiredTokenIDs.first
    }

    func refreshedTokenIDs() -> [UUID] {
        refreshedTokenIDsStorage
    }
}

private enum FileReadStub: Sendable {
    case snapshot(FileReadSnapshot)
    case missing
    case failure
}

private actor FileServiceFileSystemSpy: FileSystemAccessing {
    private var entries: [URL: FileReadSnapshot] = [:]
    private var queuedReads: [URL: [FileReadStub]] = [:]

    func read(_ url: URL) async throws -> FileReadSnapshot {
        if var stubs = queuedReads[url], !stubs.isEmpty {
            let stub = stubs.removeFirst()
            queuedReads[url] = stubs.isEmpty ? nil : stubs
            switch stub {
            case let .snapshot(snapshot):
                return snapshot
            case .missing:
                throw FileSystemAccessError.missing
            case .failure:
                throw FileSystemAccessError.readFailed
            }
        }
        guard let entry = entries[url] else {
            throw FileSystemAccessError.missing
        }
        return entry
    }

    func enqueue(_ stub: FileReadStub, for url: URL) {
        queuedReads[url, default: []].append(stub)
    }

    func set(_ url: URL, data: Data, modificationDate: Date, isWritable: Bool) {
        entries[url] = FileReadSnapshot(
            data: data,
            modificationDate: modificationDate,
            isWritable: isWritable
        )
    }

    func replace(_ url: URL, data: Data) {
        let previous = entries[url]
        entries[url] = FileReadSnapshot(
            data: data,
            modificationDate: (previous?.modificationDate ?? Date(timeIntervalSince1970: 1_000))
                .addingTimeInterval(1),
            isWritable: previous?.isWritable ?? true
        )
    }

    func remove(_ url: URL) {
        entries[url] = nil
    }

    func data(at url: URL) -> Data? {
        entries[url]?.data
    }

    func snapshot(at url: URL) -> FileReadSnapshot? {
        entries[url]
    }
}

private enum ConditionalWriteBehavior: Sendable {
    case automatic
    case result(ConditionalWriteResult)
    case writeFailure
    case readFailure
    case verificationFailure
    case unknownFailure
}

private enum ConditionalWriterSentinelError: Error, Sendable {
    case failed
}

private actor FileServiceWriterSpy: AtomicFileWriting {
    struct Write: Equatable {
        let data: Data
        let destination: URL
    }

    private let fileSystem: FileServiceFileSystemSpy
    private var verificationReplacement: Data?
    private let blockFirstWrite: Bool
    private var recordedWrites: [Write] = []
    private var recordedConditionalWrites: [Write] = []
    private var conditionalBehavior: ConditionalWriteBehavior = .automatic
    private var unconditionalWriteFails = false
    private var firstWriteStarted = false
    private var firstWriteStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstWriteRelease: CheckedContinuation<Void, Never>?

    init(
        fileSystem: FileServiceFileSystemSpy,
        verificationReplacement: Data?,
        blockFirstWrite: Bool
    ) {
        self.fileSystem = fileSystem
        self.verificationReplacement = verificationReplacement
        self.blockFirstWrite = blockFirstWrite
    }

    func write(_ data: Data, to destination: URL) async throws {
        recordedWrites.append(Write(data: data, destination: destination))
        if unconditionalWriteFails {
            throw FileServiceError.writeFailed
        }
        await blockFirstWriteIfNeeded(writeOrdinal: recordedWrites.count)
        await fileSystem.replace(destination, data: verificationReplacement ?? data)
    }

    func write(
        _ data: Data,
        to destination: URL,
        ifUnchangedFrom expected: AtomicFileVersion
    ) async throws -> ConditionalWriteResult {
        recordedConditionalWrites.append(Write(data: data, destination: destination))
        switch conditionalBehavior {
        case let .result(result):
            return result
        case .writeFailure:
            throw FileServiceError.writeFailed
        case .readFailure:
            throw AtomicFileWriterError.readFailed(destination: destination)
        case .verificationFailure:
            throw AtomicFileWriterError.verificationFailed(destination: destination)
        case .unknownFailure:
            throw ConditionalWriterSentinelError.failed
        case .automatic:
            break
        }

        guard let current = await fileSystem.snapshot(at: destination) else {
            return .missing
        }
        guard current.isWritable else {
            return .readOnly
        }
        let currentVersion = AtomicFileVersion(
            contentHash: ContentHash.sha256(current.data),
            modificationDate: current.modificationDate
        )
        guard currentVersion == expected else {
            return .conflict(currentVersion)
        }

        await blockFirstWriteIfNeeded(writeOrdinal: recordedConditionalWrites.count)
        let replacement = verificationReplacement ?? data
        await fileSystem.replace(destination, data: replacement)
        guard replacement == data,
              let verified = await fileSystem.snapshot(at: destination) else {
            throw AtomicFileWriterError.verificationFailed(destination: destination)
        }
        return .written(
            AtomicFileVersion(
                contentHash: ContentHash.sha256(verified.data),
                modificationDate: verified.modificationDate
            )
        )
    }

    private func blockFirstWriteIfNeeded(writeOrdinal: Int) async {
        if writeOrdinal == 1 {
            firstWriteStarted = true
            let waiters = firstWriteStartWaiters
            firstWriteStartWaiters = []
            waiters.forEach { $0.resume() }
            if blockFirstWrite {
                await withCheckedContinuation { continuation in
                    firstWriteRelease = continuation
                }
            }
        }
    }

    func removeIfPresent(_ url: URL) async throws {}
    func quarantine(_ source: URL, as destination: URL) async throws {}

    func writes() -> [Write] {
        recordedWrites
    }

    func writeCount() -> Int {
        recordedWrites.count + recordedConditionalWrites.count
    }

    func conditionalWriteCount() -> Int {
        recordedConditionalWrites.count
    }

    func setConditionalBehavior(_ behavior: ConditionalWriteBehavior) {
        conditionalBehavior = behavior
    }

    func setUnconditionalWriteFailure() {
        unconditionalWriteFails = true
    }

    func setVerificationReplacement(_ data: Data) {
        verificationReplacement = data
    }

    func waitUntilFirstWriteStarts() async {
        guard !firstWriteStarted else { return }
        await withCheckedContinuation { continuation in
            firstWriteStartWaiters.append(continuation)
        }
    }

    func releaseFirstWrite() {
        firstWriteRelease?.resume()
        firstWriteRelease = nil
    }
}

private actor SelectedURLEventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private enum SelectedURLBookmarkError: Error {
    case failed
}

private actor SelectedURLBookmarkSpy: BookmarkAccessing {
    private let events: SelectedURLEventRecorder
    private let storeFails: Bool

    init(events: SelectedURLEventRecorder, storeFails: Bool = false) {
        self.events = events
        self.storeFails = storeFails
    }

    func storeSelection(_ url: URL) async throws -> ExternalFileReference {
        await events.append("bookmark")
        if storeFails { throw SelectedURLBookmarkError.failed }
        return ExternalFileReference(bookmarkID: UUID(), pathHint: url.path)
    }

    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference? { nil }
    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken {
        throw SelectedURLBookmarkError.failed
    }
    func endAccess(_ token: ScopedAccessToken) async {}
    func refresh(_ token: ScopedAccessToken) async throws {}
    func forget(_ reference: ExternalFileReference) async throws {}
}

private actor SelectedURLFileSystemSpy: FileSystemAccessing {
    private let events: SelectedURLEventRecorder
    private var storedBytes: [URL: Data] = [:]

    init(events: SelectedURLEventRecorder) {
        self.events = events
    }

    func read(_ url: URL) async throws -> FileReadSnapshot {
        await events.append("verify")
        guard let data = storedBytes[url] else { throw FileSystemAccessError.missing }
        return FileReadSnapshot(
            data: data,
            modificationDate: Date(timeIntervalSince1970: 4_000),
            isWritable: true
        )
    }

    func replace(_ url: URL, with data: Data) {
        storedBytes[url] = data
    }

    func bytes(at url: URL) -> Data? {
        storedBytes[url]
    }
}

private actor SelectedURLWriterSpy: AtomicFileWriting {
    private let fileSystem: SelectedURLFileSystemSpy
    private let events: SelectedURLEventRecorder

    init(fileSystem: SelectedURLFileSystemSpy, events: SelectedURLEventRecorder) {
        self.fileSystem = fileSystem
        self.events = events
    }

    func write(_ data: Data, to destination: URL) async throws {
        try await writeSecurityScoped(data, to: destination)
    }

    func writeSecurityScoped(_ data: Data, to destination: URL) async throws {
        await events.append("write")
        await fileSystem.replace(destination, with: data)
    }

    func removeIfPresent(_ url: URL) async throws {}
    func quarantine(_ source: URL, as destination: URL) async throws {}
}
