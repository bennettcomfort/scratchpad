import Foundation

struct ApplicationSupportPaths: Sendable {
    let root: URL

    var sessionDirectory: URL {
        root.appending(path: "session", directoryHint: .isDirectory)
    }

    var recoveryDirectory: URL {
        root.appending(path: "recovery", directoryHint: .isDirectory)
    }

    var bookmarksDirectory: URL {
        root.appending(path: "bookmarks", directoryHint: .isDirectory)
    }

    var quarantineDirectory: URL {
        root.appending(path: "quarantine", directoryHint: .isDirectory)
    }

    var logsDirectory: URL {
        root.appending(path: "logs", directoryHint: .isDirectory)
    }

    var latestSession: URL {
        sessionDirectory.appending(path: "latest-session.json")
    }

    var bookmarkCollection: URL {
        bookmarksDirectory.appending(path: "bookmarks.json")
    }

    func recovery(documentID: UUID) -> URL {
        recoveryDirectory.appending(
            path: "document-\(documentID.uuidString.lowercased()).json"
        )
    }

    func quarantine(originalName: String, at date: Date) -> URL {
        let timestamp = ISO8601DateFormatter().string(from: date)
        return quarantineDirectory.appending(path: "\(timestamp)-\(originalName)")
    }

    func createDirectories(using fileManager: FileManager) throws {
        for directory in [
            sessionDirectory,
            recoveryDirectory,
            bookmarksDirectory,
            quarantineDirectory,
            logsDirectory
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}
