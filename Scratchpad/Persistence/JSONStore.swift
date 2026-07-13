import Foundation

struct JSONStore: Sendable {
    let quarantineDirectory: URL
    private let log = Log.logger("json-store")

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileWriter.write(try encoder.encode(value), to: url)
    }

    func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date())
            let dest = quarantineDirectory
                .appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
            try? FileManager.default.moveItem(at: url, to: dest)
            log.error("Quarantined corrupt file \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }
}
