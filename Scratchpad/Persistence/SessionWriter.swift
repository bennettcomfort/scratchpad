import Foundation

actor SessionWriter {
    private let paths: ApplicationSupportPaths
    private let json: JSONStore
    private let recovery: RecoveryStore
    private let log = Log.logger("session-writer")

    init(paths: ApplicationSupportPaths) {
        self.paths = paths
        self.json = JSONStore(quarantineDirectory: paths.quarantine)
        self.recovery = RecoveryStore(directory: paths.recovery, store: json)
        try? paths.ensureDirectoriesExist()
    }

    private var sessionURL: URL { paths.session.appendingPathComponent("latest-session.json") }

    func writeSession(_ s: SessionSnapshot) {
        do { try json.save(s, to: sessionURL) }
        catch { log.error("session write failed: \(error, privacy: .public)") }
    }

    func writeRecovery(_ r: RecoveryBuffer) {
        do { try recovery.write(r) }
        catch { log.error("recovery write failed: \(error, privacy: .public)") }
    }

    func deleteRecovery(bufferID: UUID) {
        do { try recovery.delete(bufferID: bufferID) }
        catch { log.error("recovery delete failed: \(error, privacy: .public)") }
    }

    func loadSession() -> SessionSnapshot? {
        (try? json.load(SessionSnapshot.self, from: sessionURL)) ?? nil
    }

    func loadRecoveries() -> [RecoveryBuffer] { (try? recovery.loadAll()) ?? [] }
}
