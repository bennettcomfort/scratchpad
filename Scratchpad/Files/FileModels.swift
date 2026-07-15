import Foundation

struct ExternalFileReference: Codable, Equatable, Sendable {
    let bookmarkID: UUID
    let pathHint: String
}

struct ScopedAccessToken: Equatable, Sendable {
    let id: UUID
    let url: URL
}

protocol BookmarkAccessing: Sendable {
    func storeSelection(_ url: URL) async throws -> ExternalFileReference
    func reference(for bookmarkID: UUID) async throws -> ExternalFileReference?
    func beginAccess(_ reference: ExternalFileReference) async throws -> ScopedAccessToken
    func endAccess(_ token: ScopedAccessToken) async
    func refresh(_ token: ScopedAccessToken) async throws
    func forget(_ reference: ExternalFileReference) async throws
}
