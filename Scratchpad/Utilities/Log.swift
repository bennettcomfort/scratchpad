import OSLog

enum AppLog {
    static let lifecycle = Logger(subsystem: "com.scratchpad.app", category: "lifecycle")
    static let persistence = Logger(subsystem: "com.scratchpad.app", category: "persistence")
    static let bookmarks = Logger(subsystem: "com.scratchpad.app", category: "bookmarks")
    static let files = Logger(subsystem: "com.scratchpad.app", category: "files")
}
