import Foundation

protocol AtomicFileWriting: Sendable {
    func write(_ data: Data, to destination: URL) async throws
    func removeIfPresent(_ url: URL) async throws
    func quarantine(_ source: URL, as destination: URL) async throws
}

protocol AtomicFileSystem: Actor {
    func exists(_ url: URL) -> Bool
    func writeAndSynchronize(_ data: Data, to temporaryURL: URL) throws
    func replace(_ destination: URL, with temporaryURL: URL) throws
    func move(_ source: URL, to destination: URL) throws
    func remove(_ url: URL) throws
}

enum AtomicFileWriterError: Error, Equatable, Sendable {
    case writeFailed(destination: URL)
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

    func replace(_ destination: URL, with temporaryURL: URL) throws {
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
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
