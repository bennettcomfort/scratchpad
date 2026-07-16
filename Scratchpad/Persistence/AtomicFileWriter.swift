import Foundation

struct AtomicFileVersion: Equatable, Sendable {
    let contentHash: String
    let modificationDate: Date
}

enum ConditionalWriteResult: Equatable, Sendable {
    case written(AtomicFileVersion)
    case conflict(AtomicFileVersion)
    case missing
    case readOnly
}

protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to destination: URL) async throws
    func writeSecurityScoped(_ data: Data, to destination: URL) async throws
    func write(
        _ data: Data,
        to destination: URL,
        ifUnchangedFrom expected: AtomicFileVersion
    ) async throws -> ConditionalWriteResult
    func removeIfPresent(_ url: URL) async throws
    func quarantine(_ source: URL, as destination: URL) async throws
}

extension AtomicFileWriting {
    func writeSecurityScoped(_ data: Data, to destination: URL) async throws {
        try await write(data, to: destination)
    }

    func write(
        _ data: Data,
        to destination: URL,
        ifUnchangedFrom expected: AtomicFileVersion
    ) async throws -> ConditionalWriteResult {
        throw AtomicFileWriterError.conditionalWriteUnavailable(destination: destination)
    }
}

protocol AtomicFileSystem: Actor {
    func exists(_ url: URL) -> Bool
    func writeAndSynchronize(_ data: Data, to temporaryURL: URL) throws
    func writeAtomicallyAndSynchronize(_ data: Data, to destination: URL) throws
    func replace(_ destination: URL, with temporaryURL: URL) throws
    func replaceIfUnchanged(
        _ data: Data,
        destination: URL,
        temporaryURL: URL,
        expected: AtomicFileVersion
    ) throws -> ConditionalWriteResult
    func move(_ source: URL, to destination: URL) throws
    func remove(_ url: URL) throws
}

enum AtomicFileWriterError: Error, Equatable, Sendable {
    case writeFailed(destination: URL)
    case readFailed(destination: URL)
    case conditionalWriteUnavailable(destination: URL)
    case verificationFailed(destination: URL)
    case removeFailed(url: URL)
    case invalidQuarantineLocation(source: URL, destination: URL)
    case quarantineFailed(source: URL, destination: URL)
}

actor AtomicFileWriter: AtomicFileWriting {
    private let fileSystem: any AtomicFileSystem
    private let canonicalRoot: URL
    private let canonicalQuarantineDirectory: URL
    private var activeDestinations: Set<URL> = []
    private var destinationWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]

    init(fileSystem: any AtomicFileSystem, paths: ApplicationSupportPaths) {
        self.fileSystem = fileSystem
        canonicalRoot = paths.root.resolvingSymlinksInPath().standardizedFileURL
        canonicalQuarantineDirectory = paths.quarantineDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    func write(_ data: Data, to destination: URL) async throws {
        let transactionKey = transactionKey(for: destination)
        await acquire(transactionKey)
        defer { release(transactionKey) }

        let temporaryURL = destination.deletingLastPathComponent().appending(
            path: ".scratchpad-\(UUID().uuidString).tmp"
        )

        do {
            try await fileSystem.writeAndSynchronize(data, to: temporaryURL)
            if await fileSystem.exists(destination) {
                try await fileSystem.replace(destination, with: temporaryURL)
            } else {
                try await fileSystem.move(temporaryURL, to: destination)
            }
        } catch {
            try? await fileSystem.remove(temporaryURL)
            throw AtomicFileWriterError.writeFailed(destination: destination)
        }
    }

    func writeSecurityScoped(_ data: Data, to destination: URL) async throws {
        let transactionKey = transactionKey(for: destination)
        await acquire(transactionKey)
        defer { release(transactionKey) }

        do {
            try await fileSystem.writeAtomicallyAndSynchronize(data, to: destination)
        } catch {
            throw AtomicFileWriterError.writeFailed(destination: destination)
        }
    }

    func write(
        _ data: Data,
        to destination: URL,
        ifUnchangedFrom expected: AtomicFileVersion
    ) async throws -> ConditionalWriteResult {
        let transactionKey = transactionKey(for: destination)
        await acquire(transactionKey)
        defer { release(transactionKey) }

        let temporaryURL = destination.deletingLastPathComponent().appending(
            path: ".scratchpad-\(UUID().uuidString).tmp"
        )

        do {
            let result = try await fileSystem.replaceIfUnchanged(
                data,
                destination: destination,
                temporaryURL: temporaryURL,
                expected: expected
            )
            if case .written = result {
                return result
            }
            try? await fileSystem.remove(temporaryURL)
            return result
        } catch let error as AtomicFileWriterError {
            try? await fileSystem.remove(temporaryURL)
            throw error
        } catch {
            try? await fileSystem.remove(temporaryURL)
            throw AtomicFileWriterError.writeFailed(destination: destination)
        }
    }

    func removeIfPresent(_ url: URL) async throws {
        let transactionKey = transactionKey(for: url)
        await acquire(transactionKey)
        defer { release(transactionKey) }

        guard await fileSystem.exists(url) else { return }
        do {
            try await fileSystem.remove(url)
        } catch {
            throw AtomicFileWriterError.removeFailed(url: url)
        }
    }

    func quarantine(_ source: URL, as destination: URL) async throws {
        let transactionKeys = transactionKeysForQuarantine(
            source: source,
            destination: destination
        )
        await acquire(transactionKeys)
        defer { release(transactionKeys) }

        guard isValidQuarantineMove(source: source, destination: destination) else {
            throw AtomicFileWriterError.invalidQuarantineLocation(
                source: source,
                destination: destination
            )
        }

        do {
            try await fileSystem.move(source, to: destination)
        } catch {
            throw AtomicFileWriterError.quarantineFailed(
                source: source,
                destination: destination
            )
        }
    }

    private func isValidQuarantineMove(source: URL, destination: URL) -> Bool {
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL
        let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        return canonicalSource.isContained(in: canonicalRoot)
            && canonicalDestination.isContained(in: canonicalRoot)
            && canonicalDestination.isContained(in: canonicalQuarantineDirectory)
    }

    func transactionKey(for destination: URL) -> URL {
        destination.resolvingSymlinksInPath().standardizedFileURL
    }

    func transactionKeysForQuarantine(source: URL, destination: URL) -> [URL] {
        Array(Set([transactionKey(for: source), transactionKey(for: destination)]))
            .sorted { $0.path < $1.path }
    }

    private func acquire(_ destinations: [URL]) async {
        for destination in destinations {
            await acquire(destination)
        }
    }

    private func release(_ destinations: [URL]) {
        for destination in destinations.reversed() {
            release(destination)
        }
    }

    private func acquire(_ destination: URL) async {
        guard activeDestinations.contains(destination) else {
            activeDestinations.insert(destination)
            return
        }

        await withCheckedContinuation { continuation in
            destinationWaiters[destination, default: []].append(continuation)
        }
    }

    private func release(_ destination: URL) {
        guard var waiters = destinationWaiters[destination], !waiters.isEmpty else {
            activeDestinations.remove(destination)
            destinationWaiters[destination] = nil
            return
        }

        let next = waiters.removeFirst()
        destinationWaiters[destination] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}

actor LiveAtomicFileSystem: AtomicFileSystem {
    private let fileManager = FileManager.default

    func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func writeAndSynchronize(_ data: Data, to temporaryURL: URL) throws {
        try data.write(to: temporaryURL)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func writeAtomicallyAndSynchronize(_ data: Data, to destination: URL) throws {
        try data.write(to: destination, options: .atomic)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func replace(_ destination: URL, with temporaryURL: URL) throws {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
    }

    func replaceIfUnchanged(
        _ data: Data,
        destination: URL,
        temporaryURL: URL,
        expected: AtomicFileVersion
    ) throws -> ConditionalWriteResult {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var coordinatedResult: Result<ConditionalWriteResult, Error>?

        coordinator.coordinate(
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let uncachedURL = URL(fileURLWithPath: coordinatedURL.path)
                guard fileManager.fileExists(atPath: uncachedURL.path) else {
                    coordinatedResult = .success(.missing)
                    return
                }
                let values: URLResourceValues
                let currentData: Data
                do {
                    values = try uncachedURL.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .isRegularFileKey,
                        .isWritableKey
                    ])
                    currentData = try Data(contentsOf: uncachedURL, options: .mappedIfSafe)
                } catch {
                    throw conditionalReadError(error, destination: destination)
                }
                guard values.isRegularFile == true,
                      let modificationDate = values.contentModificationDate else {
                    throw AtomicFileWriterError.readFailed(destination: destination)
                }
                guard values.isWritable == true else {
                    coordinatedResult = .success(.readOnly)
                    return
                }

                let currentVersion = AtomicFileVersion(
                    contentHash: ContentHash.sha256(currentData),
                    modificationDate: modificationDate
                )
                guard currentVersion == expected else {
                    coordinatedResult = .success(.conflict(currentVersion))
                    return
                }

                try writeAtomicallyAndSynchronize(data, to: uncachedURL)

                let verificationURL = URL(fileURLWithPath: coordinatedURL.path)
                let verifiedData: Data
                let verifiedValues: URLResourceValues
                do {
                    verifiedData = try Data(contentsOf: verificationURL, options: .mappedIfSafe)
                    verifiedValues = try verificationURL.resourceValues(forKeys: [
                        .contentModificationDateKey
                    ])
                } catch {
                    throw conditionalReadError(error, destination: destination)
                }
                guard verifiedData == data,
                      ContentHash.sha256(verifiedData) == ContentHash.sha256(data),
                      let verifiedModificationDate = verifiedValues.contentModificationDate else {
                    throw AtomicFileWriterError.verificationFailed(destination: destination)
                }
                coordinatedResult = .success(
                    .written(
                        AtomicFileVersion(
                            contentHash: ContentHash.sha256(verifiedData),
                            modificationDate: verifiedModificationDate
                        )
                    )
                )
            } catch {
                let cocoaError = error as NSError
                if cocoaError.domain == NSCocoaErrorDomain,
                   cocoaError.code == CocoaError.fileNoSuchFile.rawValue {
                    coordinatedResult = .success(.missing)
                } else {
                    coordinatedResult = .failure(error)
                }
            }
        }

        if let coordinatedResult {
            return try coordinatedResult.get()
        }
        if coordinationError != nil {
            throw AtomicFileWriterError.writeFailed(destination: destination)
        }
        throw AtomicFileWriterError.writeFailed(destination: destination)
    }

    private func conditionalReadError(_ error: Error, destination: URL) -> Error {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == CocoaError.fileNoSuchFile.rawValue {
            return error
        }
        return AtomicFileWriterError.readFailed(destination: destination)
    }

    func move(_ source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    func remove(_ url: URL) throws {
        try fileManager.removeItem(at: url)
    }
}

private extension URL {
    func isContained(in root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
