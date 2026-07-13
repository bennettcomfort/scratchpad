import SwiftUI
import Observation

@MainActor @Observable
final class WorkspaceModel {
    private(set) var rootURL: URL?
    private(set) var rootName: String?
    private(set) var nodes: [FileNode] = []
    private(set) var isScanning = false
    private let indexer = FileIndexer()
    private let bookmarkManager: BookmarkManager

    init(bookmarkManager: BookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    try await self.bookmarkManager.saveBookmark(for: url)
                    let didStart = try await self.bookmarkManager.startAccessing(url)
                    defer { if didStart { Task { await self.bookmarkManager.stopAccessing(url) } } }

                    self.rootURL = url
                    self.rootName = url.lastPathComponent
                    self.isScanning = true
                    self.nodes = FileNode.sortFoldersFirst(await self.indexer.scan(root: url))
                    self.isScanning = false
                } catch {
                    Log.logger("workspace").error("Open folder failed: \(error, privacy: .public)")
                }
            }
        }
    }

    func closeWorkspace() {
        rootURL = nil
        rootName = nil
        nodes = []
    }
}
