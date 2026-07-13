import AppKit

enum SaveState: String, Codable, Sendable {
    case clean, dirty, conflicted, deletedOnDisk, readOnly, scratch
}

@MainActor
final class OpenBuffer: Identifiable {
    let id: UUID
    var fileURL: URL?
    var displayName: String
    var saveState: SaveState
    private(set) var generation: Int = 0
    var cursorLocation: Int = 0
    var scrollOffsetY: Double = 0
    var lastKnownDiskMTime: Date?
    var lastSavedHash: String?
    let storage: NSTextStorage

    var text: String { storage.string }
    var firstLinePreview: String {
        String(storage.string.prefix(while: { $0 != "\n" }).prefix(60))
    }

    init(id: UUID = UUID(), fileURL: URL? = nil, displayName: String = "Scratch") {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.saveState = fileURL == nil ? .scratch : .clean
        self.storage = NSTextStorage()
    }

    /// The ONLY sanctioned whole-text write path (open / reload / restore).
    func replaceEntireContents(_ s: String) {
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: s)
        generation += 1
    }

    /// Called by the editor coordinator on every user edit.
    func noteEdited() {
        generation += 1
        if saveState == .clean { saveState = .dirty }
    }
}
