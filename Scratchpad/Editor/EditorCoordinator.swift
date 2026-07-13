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
        assert(tv.textLayoutManager != nil, "H1 violation: missing TextKit 2 — NSTextView.layoutManager downgraded to TK1")
        guard let storage = tv.textStorage,
              let font = tv.font else { return }
        let textColor = tv.textColor ?? NSColor.labelColor
        let gen = buffer.generation

        highlightDebouncer.schedule { [weak self] in
            guard let self, self.buffer.generation == gen else { return }
            let tokens = MarkdownTokenizer.tokenize(storage.string)
            HighlightApplier.apply(tokens, to: storage, font: font, textColor: textColor)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        buffer.cursorLocation = tv.selectedRange().location
    }
}
