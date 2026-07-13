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

    func textViewDidDeleteLine(_ textView: NSTextView) {
        buffer.noteEdited()
        onEdit?(buffer)
        guard let storage = textView.textStorage,
              let font = textView.font,
              storage.length < 2_000_000 else { return }
        let textColor = textView.textColor ?? NSColor.labelColor
        let tokens = MarkdownTokenizer.tokenize(storage.string)
        HighlightApplier.apply(tokens, to: storage, font: font, textColor: textColor)
        buffer.cursorLocation = textView.selectedRange().location
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.deleteToBeginningOfLine(_:)) {
            deleteCurrentLine(in: textView)
            return true
        }
        return false
    }

    private func deleteCurrentLine(in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let cursor = textView.selectedRange().location
        let text = storage.string as NSString

        let prevNL = text.range(of: "\n", options: .backwards,
                                range: NSRange(location: 0, length: cursor))
        let lineStart = prevNL.location != NSNotFound ? prevNL.upperBound : 0

        let searchRange = NSRange(location: cursor, length: storage.length - cursor)
        let nextNL = text.range(of: "\n", options: [], range: searchRange)
        let lineEnd = nextNL.location != NSNotFound ? nextNL.upperBound : storage.length

        let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        guard lineRange.length > 0 else { return }

        var deleteRange = lineRange
        if lineEnd >= storage.length, lineStart > 0 {
            let prevChar = text.substring(with: NSRange(location: lineStart - 1, length: 1))
            if prevChar == "\n" {
                deleteRange = NSRange(location: lineStart - 1, length: lineRange.length + 1)
            }
        }

        storage.replaceCharacters(in: deleteRange, with: "")
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        textViewDidDeleteLine(textView)
    }
}
