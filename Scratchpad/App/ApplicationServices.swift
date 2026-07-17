import Foundation

struct ApplicationServices: Sendable {
    let repository: any SessionPersisting
    let bookmarks: any BookmarkAccessing
    let files: any FileServicing
    let recoveryClock: any RecoveryClock

    @MainActor
    static func live(paths providedPaths: ApplicationSupportPaths? = nil) throws -> ApplicationServices {
        let paths: ApplicationSupportPaths
        if let providedPaths {
            paths = providedPaths
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            paths = ApplicationSupportPaths(
                root: applicationSupport.appending(
                    path: "Scratchpad",
                    directoryHint: .isDirectory
                )
            )
        }
        try paths.createDirectories(using: .default)

        let fileSystem = LiveAtomicFileSystem()
        let writer = AtomicFileWriter(fileSystem: fileSystem, paths: paths)
        let repository = SessionRepository(paths: paths, writer: writer)
        let bookmarks = BookmarkStore(
            paths: paths,
            writer: writer,
            client: LiveSecurityScopedBookmarkClient(),
            now: { Date() }
        )
        let files = FileService(bookmarks: bookmarks, writer: writer)
        return ApplicationServices(
            repository: repository,
            bookmarks: bookmarks,
            files: files,
            recoveryClock: ContinuousRecoveryClock()
        )
    }
}
