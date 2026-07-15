import AppKit
import Observation

@MainActor
@Observable
final class DocumentSession {
    let id: UUID
    let storage: NSTextStorage

    private(set) var fileReference: ExternalFileReference?
    private(set) var displayName: String
    private(set) var saveState: DocumentSaveState
    private(set) var hasUnsavedChanges: Bool
    private(set) var generation: Int
    private(set) var lastSavedHash: String?
    private(set) var lastKnownDiskMTime: Date?
    private(set) var lineEnding: LineEnding
    private(set) var selection: TextSelection
    private(set) var scrollOffsetY: Double
    private(set) var isPerformingWholeTextReplacement = false

    init(
        id: UUID = UUID(),
        text: String = "",
        fileReference: ExternalFileReference? = nil,
        displayName: String = "Untitled",
        saveState: DocumentSaveState = .untitled,
        hasUnsavedChanges: Bool = false,
        generation: Int = 0,
        lastSavedHash: String? = nil,
        lastKnownDiskMTime: Date? = nil,
        lineEnding: LineEnding = .lf,
        selection: TextSelection = TextSelection(location: 0, length: 0),
        scrollOffsetY: Double = 0
    ) {
        self.id = id
        self.storage = NSTextStorage(string: text)
        self.fileReference = fileReference
        self.displayName = displayName
        self.saveState = saveState
        self.hasUnsavedChanges = hasUnsavedChanges
        self.generation = generation
        self.lastSavedHash = lastSavedHash
        self.lastKnownDiskMTime = lastKnownDiskMTime
        self.lineEnding = lineEnding
        self.selection = selection.clamped(toUTF16Length: self.storage.length)
        self.scrollOffsetY = max(0, scrollOffsetY)
    }

    func replaceEntireContents(
        _ text: String,
        source: WholeTextReplacementSource,
        selection replacementSelection: TextSelection?
    ) {
        isPerformingWholeTextReplacement = true
        defer { isPerformingWholeTextReplacement = false }

        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: 0, length: storage.length),
            with: text
        )
        storage.endEditing()
        generation += 1
        selection = (replacementSelection ?? selection)
            .clamped(toUTF16Length: storage.length)

        switch source {
        case .initialUntitled:
            fileReference = nil
            displayName = "Untitled"
            saveState = .untitled
            hasUnsavedChanges = false
            lastSavedHash = nil
            lastKnownDiskMTime = nil
        case .fileOpen, .confirmedDiskReload:
            saveState = .clean
            hasUnsavedChanges = false
        case .sessionRestore:
            break
        }
    }

    func noteUserEdit() {
        generation += 1
        hasUnsavedChanges = true
        if saveState == .untitled || saveState == .clean {
            saveState = .edited
        }
    }

    func updateSelection(_ newSelection: TextSelection) {
        selection = newSelection.clamped(toUTF16Length: storage.length)
    }

    func updateScrollOffset(_ offset: Double) {
        scrollOffsetY = max(0, offset)
    }

    func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            documentID: id,
            generation: generation,
            text: storage.string,
            fileReference: fileReference,
            saveState: saveState,
            hasUnsavedChanges: hasUnsavedChanges,
            selection: selection,
            scrollOffsetY: scrollOffsetY,
            lineEnding: lineEnding,
            lastSavedHash: lastSavedHash,
            lastKnownDiskMTime: lastKnownDiskMTime
        )
    }
}
