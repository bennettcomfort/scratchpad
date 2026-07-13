import Foundation

enum FileServiceError: Error {
    case encodingFailed
    case readFailed(String)
    case stalenessConflict
    case accessDenied
    case notFileBacked
}

@MainActor
struct FileService {
    private let bookmarkManager: BookmarkManager
    private let sessionWriter: SessionWriter

    init(bookmarkManager: BookmarkManager, sessionWriter: SessionWriter) {
        self.bookmarkManager = bookmarkManager
        self.sessionWriter = sessionWriter
    }

    func open(url: URL) async throws -> (String, mtime: Date, hash: String) {
        let didStart = try await bookmarkManager.startAccessing(url)
        defer { if didStart { Task { await bookmarkManager.stopAccessing(url) } } }

        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let mtime = resourceValues.contentModificationDate else {
            throw FileServiceError.readFailed("Could not read modification date")
        }

        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)

        return (text, mtime: mtime, hash: Hashing.sha256(text))
    }

    func save(buffer: OpenBuffer) async throws {
        guard let url = buffer.fileURL else { throw FileServiceError.notFileBacked }

        let didStart = try await bookmarkManager.startAccessing(url)
        defer { if didStart { Task { await bookmarkManager.stopAccessing(url) } } }

        if FileManager.default.fileExists(atPath: url.path) {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let diskMTime = resourceValues.contentModificationDate
            guard let knownMTime = buffer.lastKnownDiskMTime,
                  let knownHash = buffer.lastSavedHash else {
                throw FileServiceError.readFailed("No prior metadata — can't verify staleness")
            }
            if diskMTime != knownMTime {
                let data = try Data(contentsOf: url)
                let diskText = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? String(decoding: data, as: UTF8.self)
                if Hashing.sha256(diskText) != knownHash {
                    throw FileServiceError.stalenessConflict
                }
            }
        }

        let text = buffer.text
        try AtomicFileWriter.write(Data(text.utf8), to: url)

        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let newMTime = resourceValues.contentModificationDate else {
            throw FileServiceError.readFailed("Could not read modification date after save")
        }
        buffer.lastKnownDiskMTime = newMTime
        buffer.lastSavedHash = Hashing.sha256(text)
        buffer.saveState = .clean

        await sessionWriter.deleteRecovery(bufferID: buffer.id)
    }

    func saveAs(buffer: OpenBuffer, to url: URL) async throws {
        try await bookmarkManager.saveBookmark(for: url)
        let didStart = try await bookmarkManager.startAccessing(url)
        defer { if didStart { Task { await bookmarkManager.stopAccessing(url) } } }

        let text = buffer.text
        try AtomicFileWriter.write(Data(text.utf8), to: url)

        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let newMTime = resourceValues.contentModificationDate else {
            throw FileServiceError.readFailed("Could not read modification date after save")
        }
        buffer.fileURL = url
        buffer.displayName = url.deletingPathExtension().lastPathComponent
        buffer.lastKnownDiskMTime = newMTime
        buffer.lastSavedHash = Hashing.sha256(text)
        buffer.saveState = .clean

        await sessionWriter.deleteRecovery(bufferID: buffer.id)
    }
}
