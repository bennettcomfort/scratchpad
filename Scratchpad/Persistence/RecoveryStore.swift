import Foundation

struct RecoveryStore: Sendable {
    let directory: URL
    let store: JSONStore

    private func url(for bufferID: UUID) -> URL {
        directory.appendingPathComponent("buffer-\(bufferID.uuidString).json")
    }

    func write(_ buffer: RecoveryBuffer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.save(buffer, to: url(for: buffer.bufferID))
    }

    func loadAll() throws -> [RecoveryBuffer] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return names.filter { $0.hasPrefix("buffer-") && $0.hasSuffix(".json") }
            .compactMap { try? store.load(RecoveryBuffer.self,
                                          from: directory.appendingPathComponent($0)) }
    }

    func delete(bufferID: UUID) throws {
        let u = url(for: bufferID)
        if FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
    }
}
