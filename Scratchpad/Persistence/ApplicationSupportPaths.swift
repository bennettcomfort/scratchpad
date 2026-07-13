import Foundation

struct ApplicationSupportPaths: Sendable {
    let root: URL
    var session: URL { root.appendingPathComponent("session") }
    var recovery: URL { root.appendingPathComponent("recovery") }
    var quarantine: URL { root.appendingPathComponent("quarantine") }
    var logs: URL { root.appendingPathComponent("logs") }

    init(root: URL) { self.root = root }

    func ensureDirectoriesExist() throws {
        for dir in [session, recovery, quarantine, logs] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func standard() throws -> ApplicationSupportPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return ApplicationSupportPaths(root: base.appendingPathComponent("Scratchpad"))
    }
}
