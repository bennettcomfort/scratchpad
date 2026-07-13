import Foundation

actor FileIndexer {
    private static let ignoreNames: Set<String> = [
        ".git", ".DS_Store", "node_modules", ".build", "DerivedData",
        "dist", "out", "target", "venv", ".env"
    ]
    private static let visibleExtensions: Set<String> = [
        "md", "markdown", "mdown", "txt"
    ]

    private let log = Log.logger("file-indexer")
    private var isScanning = false

    func scan(root: URL) async -> [FileNode] {
        guard !isScanning else { return [] }
        isScanning = true
        defer { isScanning = false }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let nodes = FileIndexer.scanSync(root: root)
                cont.resume(returning: nodes)
            }
        }
    }

    private static func scanSync(root: URL) -> [FileNode] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles) else { return [] }

        return contents.compactMap { url in
            let name = url.lastPathComponent
            guard !name.hasPrefix("."), !ignoreNames.contains(name) else { return nil }
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else { return nil }

            if isDir {
                let children = FileNode.sortFoldersFirst(scanSync(root: url))
                return FileNode(name: name, url: url, isDirectory: true, children: children)
            }
            let ext = url.pathExtension.lowercased()
            guard visibleExtensions.contains(ext) else { return nil }
            return FileNode(name: name, url: url, isDirectory: false, children: nil)
        }
    }
}
