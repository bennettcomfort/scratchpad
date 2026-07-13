import Foundation

struct FileNode: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    static func sortFoldersFirst(_ nodes: [FileNode]) -> [FileNode] {
        nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
