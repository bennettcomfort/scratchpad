import Foundation

struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

protocol SecurityScopedBookmarkClient: Sendable {
    func create(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

enum BookmarkStoreError: Error, Equatable, Sendable {
    case reselectionRequired
    case accessDenied
    case inactiveToken
    case bookmarkInUse
    case quarantineFailed(source: URL, destination: URL)
}

actor BookmarkStore: BookmarkAccessing {
    static let schemaVersion = 1

    private struct ActiveAccess: Sendable {
        let referenceID: UUID
        let url: URL
    }

    private let paths: ApplicationSupportPaths
    private let writer: any AtomicFileWriting
    private let client: any SecurityScopedBookmarkClient
    private let now: @Sendable () -> Date
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var records: [UUID: BookmarkRecord]?
    private var activeTokens: [UUID: ActiveAccess] = [:]
    private var operationIsActive = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        paths: ApplicationSupportPaths,
        writer: any AtomicFileWriting,
        client: any SecurityScopedBookmarkClient,
        now: @escaping @Sendable () -> Date
    ) {
        self.paths = paths
        self.writer = writer
        self.client = client
        self.now = now
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func storeSelection(_ url: URL) async throws -> ExternalFileReference {
        await acquireOperation()
        defer { releaseOperation() }
        return try await storeSelectionOperation(url)
    }

    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference? {
        await acquireOperation()
        defer { releaseOperation() }
        return try await referenceOperation(for: bookmarkID)
    }

    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken {
        await acquireOperation()
        defer { releaseOperation() }
        return try await beginAccessOperation(reference)
    }

    func endAccess(_ token: ScopedAccessToken) async {
        await acquireOperation()
        defer { releaseOperation() }
        await endAccessOperation(token)
    }

    func refresh(_ token: ScopedAccessToken) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try await refreshOperation(token)
    }

    func forget(_ reference: ExternalFileReference) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try await forgetOperation(reference)
    }

    private func storeSelectionOperation(
        _ url: URL
    ) async throws -> ExternalFileReference {
        try await ensureLoaded()
        let standardizedURL = url.standardizedFileURL
        let pathHint = standardizedURL.path
        let existingID = records?.values.first(where: {
            standardizedPath(forPathHint: $0.pathHint) == pathHint
        })?.id
        let record = BookmarkRecord(
            id: existingID ?? UUID(),
            bookmarkData: try client.create(for: standardizedURL),
            pathHint: pathHint,
            updatedAt: now()
        )
        let previousRecords = records
        records?[record.id] = record
        do {
            try await persist()
        } catch {
            records = previousRecords
            throw error
        }
        return makeReference(for: record)
    }

    private func referenceOperation(
        for bookmarkID: UUID
    ) async throws -> ExternalFileReference? {
        try await ensureLoaded()
        guard let record = records?[bookmarkID] else { return nil }
        return makeReference(for: record)
    }

    private func beginAccessOperation(
        _ reference: ExternalFileReference
    ) async throws -> ScopedAccessToken {
        try await ensureLoaded()
        guard var record = records?[reference.bookmarkID] else {
            throw BookmarkStoreError.reselectionRequired
        }

        let resolved: ResolvedBookmark
        do {
            resolved = try client.resolve(record.bookmarkData)
        } catch {
            throw BookmarkStoreError.reselectionRequired
        }

        if resolved.isStale {
            let previousRecords = records
            record = BookmarkRecord(
                id: record.id,
                bookmarkData: try client.create(for: resolved.url),
                pathHint: resolved.url.standardizedFileURL.path,
                updatedAt: now()
            )
            records?[record.id] = record
            do {
                try await persist()
            } catch {
                records = previousRecords
                throw error
            }
        }

        guard client.startAccessing(resolved.url) else {
            throw BookmarkStoreError.accessDenied
        }
        let token = ScopedAccessToken(id: UUID(), url: resolved.url)
        activeTokens[token.id] = ActiveAccess(referenceID: record.id, url: resolved.url)
        return token
    }

    private func endAccessOperation(_ token: ScopedAccessToken) async {
        try? await ensureLoaded()
        guard let activeAccess = activeTokens.removeValue(forKey: token.id) else { return }
        client.stopAccessing(activeAccess.url)
    }

    private func refreshOperation(_ token: ScopedAccessToken) async throws {
        try await ensureLoaded()
        guard let activeAccess = activeTokens[token.id] else {
            throw BookmarkStoreError.inactiveToken
        }
        guard let current = records?[activeAccess.referenceID] else {
            throw BookmarkStoreError.reselectionRequired
        }
        let refreshed = BookmarkRecord(
            id: current.id,
            bookmarkData: try client.create(for: activeAccess.url),
            pathHint: activeAccess.url.standardizedFileURL.path,
            updatedAt: now()
        )
        let previousRecords = records
        records?[refreshed.id] = refreshed
        do {
            try await persist()
        } catch {
            records = previousRecords
            throw error
        }
    }

    private func forgetOperation(_ reference: ExternalFileReference) async throws {
        try await ensureLoaded()
        guard records?[reference.bookmarkID] != nil else { return }
        guard !activeTokens.values.contains(where: {
            $0.referenceID == reference.bookmarkID
        }) else {
            throw BookmarkStoreError.bookmarkInUse
        }
        let previousRecords = records
        records?[reference.bookmarkID] = nil
        do {
            try await persist()
        } catch {
            records = previousRecords
            throw error
        }
    }

    private func ensureLoaded() async throws {
        guard records == nil else { return }
        let source = paths.bookmarkCollection
        guard fileManager.fileExists(atPath: source.path) else {
            records = [:]
            return
        }
        let data = try Data(contentsOf: source)

        do {
            let collection = try decoder.decode(BookmarkCollection.self, from: data)
            guard collection.schemaVersion == Self.schemaVersion else {
                throw InvalidBookmarkCollection()
            }
            var loaded: [UUID: BookmarkRecord] = [:]
            var standardizedPaths: Set<String> = []
            for record in collection.records {
                guard loaded[record.id] == nil else {
                    throw InvalidBookmarkCollection()
                }
                guard standardizedPaths.insert(
                    standardizedPath(forPathHint: record.pathHint)
                ).inserted else {
                    throw InvalidBookmarkCollection()
                }
                loaded[record.id] = record
            }
            records = loaded
        } catch {
            let destination = paths.quarantine(
                originalName: source.lastPathComponent,
                at: now()
            )
            do {
                try await writer.quarantine(source, as: destination)
            } catch {
                throw BookmarkStoreError.quarantineFailed(
                    source: source,
                    destination: destination
                )
            }
            records = [:]
        }
    }

    private func persist() async throws {
        let collection = BookmarkCollection(
            schemaVersion: Self.schemaVersion,
            records: (records ?? [:]).values.sorted {
                $0.id.uuidString < $1.id.uuidString
            }
        )
        try await writer.write(
            try encoder.encode(collection),
            to: paths.bookmarkCollection
        )
    }

    private func makeReference(for record: BookmarkRecord) -> ExternalFileReference {
        ExternalFileReference(bookmarkID: record.id, pathHint: record.pathHint)
    }

    private func standardizedPath(forPathHint pathHint: String) -> String {
        (pathHint as NSString).standardizingPath
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

struct LiveSecurityScopedBookmarkClient: SecurityScopedBookmarkClient {
    func create(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolve(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

private struct InvalidBookmarkCollection: Error {}
