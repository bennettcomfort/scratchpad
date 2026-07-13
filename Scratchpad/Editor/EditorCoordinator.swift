import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let buffer: OpenBuffer
    var onEdit: ((OpenBuffer) -> Void)?
    private let highlightDebouncer = Debouncer(delay: .milliseconds(150))
    private let log = Log.logger("editor")
    private var eventMonitor: Any?

    init(buffer: OpenBuffer) { self.buffer = buffer }

    // MARK: – Event monitor (custom shortcuts)

    func setupEventMonitor(for textView: NSTextView) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak textView] event in
            guard let self, let tv = textView else { return event }
            guard tv.window?.firstResponder === tv else { return event }

            let relevantFlags: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
            let flags = event.modifierFlags.intersection(relevantFlags)
            let char = event.charactersIgnoringModifiers ?? ""
            let keyCode = event.keyCode

            switch (flags, char, keyCode) {
            case (.command, "l", _):
                self.selectLine(in: tv)
                return nil
            case ([.command, .shift], "D", _),
                 ([.command, .shift], "d", _):
                self.duplicateLine(in: tv)
                return nil
            case ([.command, .shift], "K", _),
                 ([.command, .shift], "k", _):
                self.deleteCurrentLine(in: tv)
                return nil
            case (.command, "j", _):
                self.joinLines(in: tv)
                return nil
            case (.command, "/", _):
                self.toggleComment(in: tv)
                return nil
            case (.command, "]", _):
                self.indent(in: tv)
                return nil
            case (.command, "[", _):
                self.outdent(in: tv)
                return nil
            case (.control, "k", _),
                 (.control, "K", _):
                self.deleteToEndOfLine(in: tv)
                return nil
            case (.command, _, 36): // ⌘Enter
                self.insertLineAfter(in: tv)
                return nil
            case ([.command, .shift], _, 36): // ⌘⇧Enter
                self.insertLineBefore(in: tv)
                return nil
            case ([.command, .shift], _, 126): // ⌘⇧↑
                self.moveLineUp(in: tv)
                return nil
            case ([.command, .shift], _, 125): // ⌘⇧↓
                self.moveLineDown(in: tv)
                return nil
            case (.command, "x", _):
                if tv.selectedRange().length == 0 {
                    self.cutLine(in: tv)
                    return nil
                }
                return event
            case (.command, "c", _):
                if tv.selectedRange().length == 0 {
                    self.copyLine(in: tv)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: – NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        buffer.noteEdited()
        onEdit?(buffer)
        scheduleHighlight(notification)
    }

    private func scheduleHighlight(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView,
              tv.string.utf8.count < 2_000_000 else { return }
        assert(tv.textLayoutManager != nil, "H1 violation: missing TextKit 2")
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

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.deleteToBeginningOfLine(_:)) {
            deleteCurrentLine(in: textView)
            return true
        }
        return false
    }

    // MARK: – Helpers

    private func lineRange(at location: Int, in text: NSString) -> NSRange {
        let loc = max(0, min(location, text.length > 0 ? text.length - 1 : 0))
        return text.lineRange(for: NSRange(location: loc, length: 0))
    }

    private func selectedLineRange(in textView: NSTextView) -> NSRange {
        let sel = textView.selectedRange()
        let text = textView.string as NSString
        let startLine = lineRange(at: sel.location, in: text)
        let endLocation = max(sel.location, sel.upperBound - 1)
        let endLine = lineRange(at: endLocation, in: text)
        return NSRange(location: startLine.location, length: endLine.upperBound - startLine.location)
    }

    private func noteEditAndRehighlight(_ textView: NSTextView) {
        buffer.noteEdited()
        onEdit?(buffer)
        buffer.cursorLocation = textView.selectedRange().location
        guard let storage = textView.textStorage,
              let font = textView.font,
              storage.length < 2_000_000 else { return }
        let textColor = textView.textColor ?? NSColor.labelColor
        let tokens = MarkdownTokenizer.tokenize(storage.string)
        HighlightApplier.apply(tokens, to: storage, font: font, textColor: textColor)
    }

    // MARK: – Commands

    private func selectLine(in textView: NSTextView) {
        let line = selectedLineRange(in: textView)
        textView.setSelectedRange(line)
        buffer.cursorLocation = line.location
    }

    private func duplicateLine(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let line = selectedLineRange(in: textView)
        let text = storage.string as NSString
        let lineText = text.substring(with: line)
        storage.replaceCharacters(in: NSRange(location: line.upperBound, length: 0), with: lineText)
        textView.setSelectedRange(NSRange(location: line.upperBound + line.length, length: 0))
        noteEditAndRehighlight(textView)
    }

    private func deleteCurrentLine(in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let line = selectedLineRange(in: textView)
        let text = storage.string as NSString

        var deleteRange = line
        // If last line has no newline but there's a line before it, eat the previous newline too
        if line.upperBound >= text.length, line.location > 0 {
            let prevChar = text.substring(with: NSRange(location: line.location - 1, length: 1))
            if prevChar == "\n" {
                deleteRange = NSRange(location: line.location - 1, length: line.length + 1)
            }
        }

        storage.replaceCharacters(in: deleteRange, with: "")
        let newCursor = min(line.location, storage.length)
        textView.setSelectedRange(NSRange(location: newCursor, length: 0))
        noteEditAndRehighlight(textView)
    }

    private func moveLineUp(in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let sel = textView.selectedRange()
        let text = storage.string as NSString

        let startLine = lineRange(at: sel.location, in: text)
        let endLocation = max(sel.location, sel.upperBound - 1)
        let endLine = lineRange(at: endLocation, in: text)

        guard startLine.location > 0 else { return }

        let prevLine = lineRange(at: startLine.location - 1, in: text)
        let selectedText = text.substring(with: NSRange(location: startLine.location,
                                                         length: endLine.upperBound - startLine.location))
        let prevText = text.substring(with: prevLine)
        let combinedRange = NSRange(location: prevLine.location,
                                     length: endLine.upperBound - prevLine.location)
        storage.replaceCharacters(in: combinedRange, with: selectedText + prevText)

        let cursorOffset = sel.location - startLine.location
        textView.setSelectedRange(NSRange(location: prevLine.location + cursorOffset, length: sel.length))
        noteEditAndRehighlight(textView)
    }

    private func moveLineDown(in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let sel = textView.selectedRange()
        let text = storage.string as NSString

        let startLine = lineRange(at: sel.location, in: text)
        let endLocation = max(sel.location, sel.upperBound - 1)
        let endLine = lineRange(at: endLocation, in: text)

        guard endLine.upperBound < text.length else { return }

        let nextLine = lineRange(at: endLine.upperBound, in: text)
        let selectedText = text.substring(with: NSRange(location: startLine.location,
                                                         length: endLine.upperBound - startLine.location))
        let nextText = text.substring(with: nextLine)
        let combinedRange = NSRange(location: startLine.location,
                                     length: nextLine.upperBound - startLine.location)
        storage.replaceCharacters(in: combinedRange, with: nextText + selectedText)

        let cursorOffset = sel.location - startLine.location
        let nextLength = (nextText as NSString).length
        textView.setSelectedRange(NSRange(location: startLine.location + nextLength + cursorOffset,
                                           length: sel.length))
        noteEditAndRehighlight(textView)
    }

    private func deleteToEndOfLine(in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let cursor = textView.selectedRange().location
        let text = storage.string as NSString
        let currentLineRange = self.lineRange(at: cursor, in: text)
        let lineText = text.substring(with: currentLineRange)
        let contentEnd = lineText.hasSuffix("\n") ? currentLineRange.upperBound - 1 : currentLineRange.upperBound
        let deleteRange = NSRange(location: cursor, length: contentEnd - cursor)
        guard deleteRange.length > 0 else { return }
        storage.replaceCharacters(in: deleteRange, with: "")
        noteEditAndRehighlight(textView)
    }

    private func joinLines(in textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let cursor = textView.selectedRange().location
        let text = storage.string as NSString
        let currentLineRange = self.lineRange(at: cursor, in: text)
        guard currentLineRange.upperBound < text.length else { return }

        let newlineRange = NSRange(location: currentLineRange.upperBound - 1, length: 1)
        guard text.substring(with: newlineRange) == "\n" else { return }

        // Determine if a space is needed between the joined lines
        let currentContent = text.substring(with: NSRange(location: currentLineRange.location,
                                                           length: currentLineRange.length - 1))
        let nextLine = self.lineRange(at: currentLineRange.upperBound, in: text)
        let nextContent = text.substring(with: NSRange(location: nextLine.location,
                                                        length: nextLine.length - 1))

        let currentEndsWithWS = currentContent.hasSuffix(" ") || currentContent.hasSuffix("\t")
        let nextStartsWithWS = nextContent.hasPrefix(" ") || nextContent.hasPrefix("\t")
        let needsSpace = !currentContent.isEmpty && !nextContent.isEmpty
                         && !currentEndsWithWS && !nextStartsWithWS

        let replacement = needsSpace ? " " : ""
        storage.replaceCharacters(in: newlineRange, with: replacement)
        textView.setSelectedRange(NSRange(location: newlineRange.location + replacement.utf16.count, length: 0))
        noteEditAndRehighlight(textView)
    }

    private func toggleComment(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        let text = storage.string as NSString

        let startLine = lineRange(at: sel.location, in: text)
        let endLocation = max(sel.location, sel.upperBound - 1)
        let endLine = lineRange(at: endLocation, in: text)
        let fullRange = NSRange(location: startLine.location,
                                 length: endLine.upperBound - startLine.location)

        let fullText = text.substring(with: fullRange)
        var lines = fullText.components(separatedBy: "\n")

        // Remove trailing empty string caused by trailing newline
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }

        let allCommented = lines.allSatisfy { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || trimmed.hasPrefix("//")
        }

        let newLines = lines.map { line -> String in
            let ws = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            let rest = line.dropFirst(ws.count)
            if allCommented {
                if rest.hasPrefix("// ") {
                    return ws + String(rest.dropFirst(3))
                } else if rest.hasPrefix("//") {
                    return ws + String(rest.dropFirst(2))
                }
            } else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    return ws + "// " + String(rest)
                }
            }
            return line
        }

        // Preserve trailing newline if original had one
        let hadTrailingNewline = fullText.hasSuffix("\n")
        var newText = newLines.joined(separator: "\n")
        if hadTrailingNewline {
            newText += "\n"
        }

        storage.replaceCharacters(in: fullRange, with: newText)
        noteEditAndRehighlight(textView)
    }

    private func indent(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        let text = storage.string as NSString

        let startLine = lineRange(at: sel.location, in: text)
        let endLocation = max(sel.location, sel.upperBound - 1)
        let endLine = lineRange(at: endLocation, in: text)
        let fullRange = NSRange(location: startLine.location,
                                 length: endLine.upperBound - startLine.location)

        let fullText = text.substring(with: fullRange)
        let lines = fullText.components(separatedBy: "\n")
        let newLines = lines.map { "\t" + $0 }
        let newText = newLines.joined(separator: "\n")

        storage.replaceCharacters(in: fullRange, with: newText)
        noteEditAndRehighlight(textView)
    }

    private func outdent(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        let text = storage.string as NSString

        let startLine = lineRange(at: sel.location, in: text)
        let endLocation = max(sel.location, sel.upperBound - 1)
        let endLine = lineRange(at: endLocation, in: text)
        let fullRange = NSRange(location: startLine.location,
                                 length: endLine.upperBound - startLine.location)

        let fullText = text.substring(with: fullRange)
        let lines = fullText.components(separatedBy: "\n")
        let newLines = lines.map { line -> String in
            if line.hasPrefix("\t") {
                return String(line.dropFirst())
            } else if line.hasPrefix("    ") {
                return String(line.dropFirst(4))
            } else if line.hasPrefix("  ") {
                return String(line.dropFirst(2))
            } else if line.hasPrefix(" ") {
                return String(line.dropFirst())
            }
            return line
        }
        let newText = newLines.joined(separator: "\n")

        storage.replaceCharacters(in: fullRange, with: newText)
        noteEditAndRehighlight(textView)
    }

    private func insertLineAfter(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let line = selectedLineRange(in: textView)
        let insertPos = line.upperBound
        storage.replaceCharacters(in: NSRange(location: insertPos, length: 0), with: "\n")
        textView.setSelectedRange(NSRange(location: insertPos + 1, length: 0))
        noteEditAndRehighlight(textView)
    }

    private func insertLineBefore(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let line = selectedLineRange(in: textView)
        storage.replaceCharacters(in: NSRange(location: line.location, length: 0), with: "\n")
        textView.setSelectedRange(NSRange(location: line.location, length: 0))
        noteEditAndRehighlight(textView)
    }

    private func cutLine(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let line = selectedLineRange(in: textView)
        let text = storage.string as NSString
        let lineText = text.substring(with: line)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lineText, forType: .string)
        storage.replaceCharacters(in: line, with: "")
        noteEditAndRehighlight(textView)
    }

    private func copyLine(in textView: NSTextView) {
        let line = selectedLineRange(in: textView)
        let text = textView.string as NSString
        let lineText = text.substring(with: line)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lineText, forType: .string)
    }
}
