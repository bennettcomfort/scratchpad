import Foundation

struct FileReadSnapshot: Equatable, Sendable {
    let data: Data
    let modificationDate: Date
    let isWritable: Bool
}

enum FileSystemAccessError: Error, Equatable, Sendable {
    case missing
    case readFailed
}

protocol FileSystemAccessing: Sendable {
    func read(_ url: URL) async throws -> FileReadSnapshot
}

struct LiveFileSystemAccess: FileSystemAccessing {
    func read(_ url: URL) async throws -> FileReadSnapshot {
        let uncachedURL = URL(fileURLWithPath: url.path)
        guard FileManager.default.fileExists(atPath: uncachedURL.path) else {
            throw FileSystemAccessError.missing
        }
        let values: URLResourceValues
        do {
            values = try uncachedURL.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
                .isWritableKey
            ])
        } catch {
            throw mapReadError(error)
        }

        guard values.isRegularFile != false,
              let modificationDate = values.contentModificationDate else {
            throw FileSystemAccessError.readFailed
        }

        let data: Data
        do {
            data = try Data(contentsOf: uncachedURL, options: .mappedIfSafe)
        } catch {
            throw mapReadError(error)
        }

        return FileReadSnapshot(
            data: data,
            modificationDate: modificationDate,
            isWritable: values.isWritable == true
        )
    }

    private func mapReadError(_ error: Error) -> FileSystemAccessError {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == CocoaError.fileNoSuchFile.rawValue {
            return .missing
        }
        return .readFailed
    }
}

actor FileService: FileServicing {
    private let bookmarks: any BookmarkAccessing
    private let writer: any AtomicFileWriting
    private let fileSystem: any FileSystemAccessing
    private var operationIsActive = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        bookmarks: any BookmarkAccessing,
        writer: any AtomicFileWriting,
        fileSystem: any FileSystemAccessing = LiveFileSystemAccess()
    ) {
        self.bookmarks = bookmarks
        self.writer = writer
        self.fileSystem = fileSystem
    }

    func open(_ reference: ExternalFileReference) async throws -> FileOpenResult {
        await acquireOperation()
        defer { releaseOperation() }
        return try await openOperation(reference)
    }

    func save(_ snapshot: DocumentSnapshot) async throws -> FileSaveResult {
        await acquireOperation()
        defer { releaseOperation() }
        return try await saveOperation(snapshot)
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        await acquireOperation()
        defer { releaseOperation() }
        return try await saveAsOperation(snapshot, to: reference)
    }

    func saveAs(
        _ snapshot: DocumentSnapshot,
        toSelectedURL url: URL
    ) async throws -> FileSaveResult {
        await acquireOperation()
        defer { releaseOperation() }
        return try await saveAsSelectedURLOperation(snapshot, to: url)
    }

    func inspect(_ snapshot: DocumentSnapshot) async throws -> ExternalFileStatus {
        await acquireOperation()
        defer { releaseOperation() }
        return try await inspectOperation(snapshot)
    }

    private func openOperation(
        _ reference: ExternalFileReference
    ) async throws -> FileOpenResult {
        let token = try await beginAccess(reference)
        do {
            let disk = try await read(token.url)
            guard let decoded = String(data: disk.data, encoding: .utf8) else {
                throw FileServiceError.invalidUTF8
            }
            let lineEnding: LineEnding = disk.data.range(of: Data([0x0D, 0x0A])) == nil
                ? .lf
                : .crlf
            let result = FileOpenResult(
                reference: reference,
                text: normalizeLineEndings(decoded),
                displayName: token.url.lastPathComponent,
                lineEnding: lineEnding,
                contentHash: ContentHash.sha256(disk.data),
                modificationDate: disk.modificationDate
            )
            await bookmarks.endAccess(token)
            return result
        } catch {
            await bookmarks.endAccess(token)
            throw mapOperationError(error)
        }
    }

    private func saveOperation(
        _ snapshot: DocumentSnapshot
    ) async throws -> FileSaveResult {
        guard let reference = snapshot.fileReference else {
            throw FileServiceError.missingFileReference
        }
        guard let baseHash = snapshot.lastSavedHash,
              let baseModificationDate = snapshot.lastKnownDiskMTime else {
            throw FileServiceError.missingBaseMetadata
        }

        let token = try await beginAccess(reference)
        do {
            let current = try await read(token.url)
            guard current.isWritable else {
                throw FileServiceError.readOnly
            }
            let currentHash = ContentHash.sha256(current.data)
            guard currentHash == baseHash,
                  current.modificationDate == baseModificationDate else {
                throw FileServiceError.conflict(
                    contentHash: currentHash,
                    modificationDate: current.modificationDate
                )
            }
            let requestedBytes = encodedBytes(for: snapshot)
            let expected = AtomicFileVersion(
                contentHash: baseHash,
                modificationDate: baseModificationDate
            )
            let outcome: ConditionalWriteResult
            do {
                outcome = try await writer.write(
                    requestedBytes,
                    to: token.url,
                    ifUnchangedFrom: expected
                )
            } catch AtomicFileWriterError.readFailed {
                throw FileServiceError.readFailed
            } catch AtomicFileWriterError.verificationFailed {
                throw FileServiceError.verificationFailed
            } catch {
                throw FileServiceError.writeFailed
            }
            let result: FileSaveResult
            switch outcome {
            case let .written(version):
                try await bookmarks.refresh(token)
                result = makeSaveResult(
                    snapshot,
                    reference: reference,
                    destination: token.url,
                    version: version
                )
            case let .conflict(version):
                throw FileServiceError.conflict(
                    contentHash: version.contentHash,
                    modificationDate: version.modificationDate
                )
            case .missing:
                throw FileServiceError.missing
            case .readOnly:
                throw FileServiceError.readOnly
            }
            await bookmarks.endAccess(token)
            return result
        } catch {
            await bookmarks.endAccess(token)
            throw mapOperationError(error)
        }
    }

    private func saveAsOperation(
        _ snapshot: DocumentSnapshot,
        to reference: ExternalFileReference
    ) async throws -> FileSaveResult {
        let token = try await beginAccess(reference)
        do {
            do {
                let current = try await fileSystem.read(token.url)
                guard current.isWritable else {
                    throw FileServiceError.readOnly
                }
            } catch FileSystemAccessError.missing {
                // The selected destination may be a new file.
            }
            let result = try await writeAndVerifyUnconditionally(
                snapshot,
                reference: reference,
                destination: token.url
            )
            try await bookmarks.refresh(token)
            await bookmarks.endAccess(token)
            return result
        } catch {
            await bookmarks.endAccess(token)
            throw mapOperationError(error)
        }
    }

    private func saveAsSelectedURLOperation(
        _ snapshot: DocumentSnapshot,
        to destination: URL
    ) async throws -> FileSaveResult {
        let requestedBytes = encodedBytes(for: snapshot)

        do {
            try await writer.writeSecurityScoped(requestedBytes, to: destination)
        } catch {
            throw FileServiceError.writeFailed
        }

        let verified = try await read(destination)
        let requestedHash = ContentHash.sha256(requestedBytes)
        guard verified.data == requestedBytes,
              ContentHash.sha256(verified.data) == requestedHash else {
            throw FileServiceError.verificationFailed
        }

        let reference: ExternalFileReference
        do {
            reference = try await bookmarks.storeSelection(destination)
        } catch {
            throw FileServiceError.accessFailed
        }

        return FileSaveResult(
            documentID: snapshot.documentID,
            initiatingGeneration: snapshot.generation,
            reference: reference,
            displayName: destination.lastPathComponent,
            lineEnding: snapshot.lineEnding,
            contentHash: requestedHash,
            modificationDate: verified.modificationDate
        )
    }

    private func inspectOperation(
        _ snapshot: DocumentSnapshot
    ) async throws -> ExternalFileStatus {
        guard let reference = snapshot.fileReference else {
            throw FileServiceError.missingFileReference
        }

        let token: ScopedAccessToken
        do {
            token = try await bookmarks.beginAccess(reference)
        } catch BookmarkStoreError.reselectionRequired {
            return .accessRequiresReselection
        } catch BookmarkStoreError.accessDenied {
            return .readOnly
        } catch {
            throw FileServiceError.accessFailed
        }

        do {
            let current: FileReadSnapshot
            do {
                current = try await fileSystem.read(token.url)
            } catch FileSystemAccessError.missing {
                await bookmarks.endAccess(token)
                return .missing
            }
            guard current.isWritable else {
                await bookmarks.endAccess(token)
                return .readOnly
            }
            let currentHash = ContentHash.sha256(current.data)
            let result: ExternalFileStatus
            if currentHash == snapshot.lastSavedHash,
               current.modificationDate == snapshot.lastKnownDiskMTime {
                result = .unchanged
            } else {
                result = .changed(
                    contentHash: currentHash,
                    modificationDate: current.modificationDate
                )
            }
            await bookmarks.endAccess(token)
            return result
        } catch {
            await bookmarks.endAccess(token)
            throw mapOperationError(error)
        }
    }

    private func writeAndVerifyUnconditionally(
        _ snapshot: DocumentSnapshot,
        reference: ExternalFileReference,
        destination: URL
    ) async throws -> FileSaveResult {
        let requestedBytes = encodedBytes(for: snapshot)

        do {
            try await writer.writeSecurityScoped(requestedBytes, to: destination)
        } catch {
            throw FileServiceError.writeFailed
        }

        let verified = try await read(destination)
        let requestedHash = ContentHash.sha256(requestedBytes)
        guard verified.data == requestedBytes,
              ContentHash.sha256(verified.data) == requestedHash else {
            throw FileServiceError.verificationFailed
        }

        return FileSaveResult(
            documentID: snapshot.documentID,
            initiatingGeneration: snapshot.generation,
            reference: reference,
            displayName: destination.lastPathComponent,
            lineEnding: snapshot.lineEnding,
            contentHash: requestedHash,
            modificationDate: verified.modificationDate
        )
    }

    private func encodedBytes(for snapshot: DocumentSnapshot) -> Data {
        snapshot.persistedBytes
    }

    private func makeSaveResult(
        _ snapshot: DocumentSnapshot,
        reference: ExternalFileReference,
        destination: URL,
        version: AtomicFileVersion
    ) -> FileSaveResult {
        FileSaveResult(
            documentID: snapshot.documentID,
            initiatingGeneration: snapshot.generation,
            reference: reference,
            displayName: destination.lastPathComponent,
            lineEnding: snapshot.lineEnding,
            contentHash: version.contentHash,
            modificationDate: version.modificationDate
        )
    }

    private func beginAccess(
        _ reference: ExternalFileReference
    ) async throws -> ScopedAccessToken {
        do {
            return try await bookmarks.beginAccess(reference)
        } catch BookmarkStoreError.reselectionRequired {
            throw FileServiceError.accessRequiresReselection
        } catch BookmarkStoreError.accessDenied {
            throw FileServiceError.readOnly
        } catch {
            throw FileServiceError.accessFailed
        }
    }

    private func read(_ url: URL) async throws -> FileReadSnapshot {
        do {
            return try await fileSystem.read(url)
        } catch FileSystemAccessError.missing {
            throw FileServiceError.missing
        } catch {
            throw FileServiceError.readFailed
        }
    }

    private func mapOperationError(_ error: Error) -> FileServiceError {
        if let serviceError = error as? FileServiceError {
            return serviceError
        }
        if let fileSystemError = error as? FileSystemAccessError {
            switch fileSystemError {
            case .missing:
                return .missing
            case .readFailed:
                return .readFailed
            }
        }
        if let writerError = error as? AtomicFileWriterError {
            switch writerError {
            case .readFailed:
                return .readFailed
            case .verificationFailed:
                return .verificationFailed
            case .writeFailed, .conditionalWriteUnavailable:
                return .writeFailed
            case .removeFailed, .invalidQuarantineLocation, .quarantineFailed:
                return .writeFailed
            }
        }
        return .readFailed
    }

    private func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func acquireOperation() async {
        guard operationIsActive else {
            operationIsActive = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationIsActive = false
            return
        }
        let next = operationWaiters.removeFirst()
        next.resume()
    }
}
