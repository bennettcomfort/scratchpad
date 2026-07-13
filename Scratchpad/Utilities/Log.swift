import os

enum Log {
    static func logger(_ category: String) -> Logger {
        Logger(subsystem: "com.scratchpad.app", category: category)
    }
}
