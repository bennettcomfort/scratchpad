import Foundation

protocol SessionPersisting: Sendable {
    func loadSession() async throws -> SessionRecord?
    func writeSession(_ record: SessionRecord) async throws
    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord?
    func loadAllRecovery() async throws -> [RecoveryRecord]
    func writeRecovery(_ record: RecoveryRecord) async throws
    func deleteRecovery(documentID: UUID) async throws
}

enum SessionRepositoryError: Error, Equatable, Sendable {
    case quarantineFailed(source: URL, destination: URL)
    case unsupportedSchema(expected: Int, actual: Int)
}

actor SessionRepository: SessionPersisting {
    static let schemaVersion = 1

    private let paths: ApplicationSupportPaths
    private let writer: any AtomicFileWriting
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager = FileManager.default

    init(paths: ApplicationSupportPaths, writer: any AtomicFileWriting) {
        self.paths = paths
        self.writer = writer
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func loadSession() async throws -> SessionRecord? {
        try await load(SessionRecord.self, from: paths.latestSession)
    }

    func writeSession(_ record: SessionRecord) async throws {
        try validateWritableSchema(record.schemaVersion)
        try await writer.write(try encoder.encode(record), to: paths.latestSession)
    }

    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? {
        try await load(
            RecoveryRecord.self,
            from: paths.recovery(documentID: documentID),
            validate: { $0.documentID == documentID }
        )
    }

    func loadAllRecovery() async throws -> [RecoveryRecord] {
        guard fileManager.fileExists(atPath: paths.recoveryDirectory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: paths.recoveryDirectory,
            includingPropertiesForKeys: nil
        )
        var records: [RecoveryRecord] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let documentID = recoveryDocumentID(from: file) else { continue }
            if let record = try await loadRecovery(documentID: documentID) {
                records.append(record)
            }
        }
        return records
    }

    func writeRecovery(_ record: RecoveryRecord) async throws {
        try validateWritableSchema(record.schemaVersion)
        try await writer.write(
            try encoder.encode(record),
            to: paths.recovery(documentID: record.documentID)
        )
    }

    func deleteRecovery(documentID: UUID) async throws {
        try await writer.removeIfPresent(paths.recovery(documentID: documentID))
    }

    private func load<Record: Decodable & SchemaVersioned>(
        _ type: Record.Type,
        from source: URL,
        validate: (Record) -> Bool = { _ in true }
    ) async throws -> Record? {
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        let data = try Data(contentsOf: source)

        do {
            let record = try decoder.decode(type, from: data)
            guard record.schemaVersion == Self.schemaVersion else {
                throw UnsupportedSchemaError()
            }
            guard validate(record) else {
                throw InvalidRecordError()
            }
            return record
        } catch {
            try await quarantine(source)
            return nil
        }
    }

    private func quarantine(_ source: URL) async throws {
        let destination = paths.quarantine(
            originalName: source.lastPathComponent,
            at: Date()
        )
        do {
            try await writer.quarantine(source, as: destination)
        } catch {
            throw SessionRepositoryError.quarantineFailed(
                source: source,
                destination: destination
            )
        }
    }

    private func recoveryDocumentID(from url: URL) -> UUID? {
        guard url.pathExtension == "json" else { return nil }
        let filename = url.deletingPathExtension().lastPathComponent
        let prefix = "document-"
        guard filename.hasPrefix(prefix) else { return nil }
        guard let documentID = UUID(
            uuidString: String(filename.dropFirst(prefix.count))
        ) else { return nil }
        guard url.lastPathComponent == paths.recovery(documentID: documentID).lastPathComponent else {
            return nil
        }
        return documentID
    }

    private func validateWritableSchema(_ schemaVersion: Int) throws {
        guard schemaVersion == Self.schemaVersion else {
            throw SessionRepositoryError.unsupportedSchema(
                expected: Self.schemaVersion,
                actual: schemaVersion
            )
        }
    }
}

private protocol SchemaVersioned {
    var schemaVersion: Int { get }
}

extension SessionRecord: SchemaVersioned {}
extension RecoveryRecord: SchemaVersioned {}

private struct UnsupportedSchemaError: Error {}
private struct InvalidRecordError: Error {}
