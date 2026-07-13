import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let buffer: OpenBuffer
    var onEdit: ((OpenBuffer) -> Void)?
    private let highlightDebouncer = Debouncer(delay: .milliseconds(150))
    private let log = Log.logger("editor")

    init(buffer: OpenBuffer) { self.buffer = buffer }

    func textDidChange(_ notification: Notification) {
        buffer.noteEdited()
        onEdit?(buffer)
        scheduleHighlight(notification)
    }

    private func scheduleHighlight(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView,
              tv.string.utf8.count < 2_000_000 else { return }

        let storage = tv.textStorage
        guard let storage else { return }
        let font = tv.font ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let gen = buffer.generation

        highlightDebouncer.schedule { [weak self] in
            self?.runHighlight(storage: storage, font: font, generation: gen)
        }
    }

    private func runHighlight(storage: NSTextStorage, font: NSFont, generation: Int) {
        let text = storage.string
        let fontSize = font.pointSize
        // Tokenize on a background queue (pure function, no AppKit).
        Task.detached(priority: .medium) {
            let tokens = MarkdownTokenizer.tokenize(text)
            let bgFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            await MainActor.run { [weak self] in
                guard let self, self.buffer.generation == generation else { return }
                HighlightApplier.apply(tokens, to: storage, font: bgFont)
            }
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        buffer.cursorLocation = tv.selectedRange().location
    }
}
