import Foundation

struct ExternalFileReference: Codable, Equatable, Sendable {
    let bookmarkID: UUID
    let pathHint: String
}
