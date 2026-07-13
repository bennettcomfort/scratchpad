import Foundation

actor BookmarkManager {
    private var bookmarks: [URL: Data] = [:]

    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        bookmarks[url] = data
    }

    func resolve(_ url: URL) throws -> URL? {
        guard let data = bookmarks[url] else { return nil }
        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale)
        if stale, let fresh = try? resolved.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[url] = fresh
        }
        return resolved
    }

    func startAccessing(_ url: URL) throws -> Bool {
        guard let resolved = try resolve(url) else { return false }
        return resolved.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        if let resolved = try? resolve(url) {
            resolved.stopAccessingSecurityScopedResource()
        }
    }

    func forget(_ url: URL) {
        bookmarks[url] = nil
    }
}
