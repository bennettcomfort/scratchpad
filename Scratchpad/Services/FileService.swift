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
    private let bufferStore: BufferStore
    private let log = Log.logger("file")

    init(bookmarkManager: BookmarkManager, sessionWriter: SessionWriter, bufferStore: BufferStore) {
        self.bookmarkManager = bookmarkManager
        self.sessionWriter = sessionWriter
        self.bufferStore = bufferStore
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

    // MARK: - External change polling

    /// Called by FileWatcher every ~2 seconds. Checks all open file-backed buffers
    /// for external modifications and applies the matrix.
    func pollExternalChanges() async {
        for buffer in bufferStore.buffers {
            guard let url = buffer.fileURL else { continue }
            guard let didStart = try? await bookmarkManager.startAccessing(url) else { continue }
            defer { if didStart { Task { await bookmarkManager.stopAccessing(url) } } }

            // Deleted-on-disk check.
            guard FileManager.default.fileExists(atPath: url.path) else {
                if buffer.saveState != .deletedOnDisk {
                    buffer.saveState = .deletedOnDisk
                    log.notice("File deleted on disk: \(buffer.displayName, privacy: .public)")
                }
                continue
            }

            // If previously marked deleted but file reappeared, clear the state.
            if buffer.saveState == .deletedOnDisk {
                buffer.saveState = buffer.lastSavedHash != nil ? .clean : .scratch
            }

            guard let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let diskMTime = resourceValues.contentModificationDate else { continue }

            guard let knownMTime = buffer.lastKnownDiskMTime,
                  let knownHash = buffer.lastSavedHash else { continue }

            // No change.
            guard diskMTime != knownMTime else { continue }

            // mtime changed — verify via hash.
            guard let data = try? Data(contentsOf: url),
                  let diskText = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else { continue }
            let diskHash = Hashing.sha256(diskText)
            guard diskHash != knownHash else { continue }

            // Content actually changed. Apply matrix.
            switch buffer.saveState {
            case .clean:
                // Clean + modified on disk → silent reload.
                buffer.replaceEntireContents(diskText)
                buffer.lastKnownDiskMTime = diskMTime
                buffer.lastSavedHash = diskHash
                log.notice("Silently reloaded clean buffer: \(buffer.displayName, privacy: .public)")

            case .dirty:
                // Dirty + modified on disk → conflict.
                buffer.saveState = .conflicted
                log.notice("Conflict detected: \(buffer.displayName, privacy: .public)")

            default:
                break // conflicted, deletedOnDisk, readOnly, scratch — no-op
            }
        }
    }
}
