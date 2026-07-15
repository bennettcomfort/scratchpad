import AppKit

@MainActor
final class ScratchTextView: NSTextView {
    var commandContext = EditorCommandContext.defaults(lineEnding: .lf)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.makeFirstResponder(self) }
    }

    @objc func scratchpadDuplicateLine(_ sender: Any?) { perform(.duplicateLine) }
    @objc func scratchpadDeleteLine(_ sender: Any?) { perform(.deleteLine) }
    @objc func scratchpadMoveLinesUp(_ sender: Any?) { perform(.moveLinesUp) }
    @objc func scratchpadMoveLinesDown(_ sender: Any?) { perform(.moveLinesDown) }
    @objc func scratchpadSelectLine(_ sender: Any?) { perform(.selectLine) }
    @objc func scratchpadJoinLines(_ sender: Any?) { perform(.joinLines) }
    @objc func scratchpadIndent(_ sender: Any?) { perform(.indent) }
    @objc func scratchpadOutdent(_ sender: Any?) { perform(.outdent) }
    @objc func scratchpadInsertLineAfter(_ sender: Any?) { perform(.insertLineAfter) }
    @objc func scratchpadInsertLineBefore(_ sender: Any?) { perform(.insertLineBefore) }

    private func perform(_ command: EditorCommand) {
        guard let outcome = EditorCommandRouter.outcome(
            for: command,
            text: string,
            selection: selectedRange(),
            context: commandContext
        ) else { return }
        switch outcome {
        case .selection(let selection):
            setSelectedRange(selection)
        case .edit(let edit):
            apply(edit)
        }
    }

    private func apply(_ edit: TextEdit) {
        let ranges = edit.mutations.map { NSValue(range: $0.range) }
        let replacements = edit.mutations.map(\.replacementText)
        guard shouldChangeText(
            inRanges: ranges,
            replacementStrings: replacements
        ) else { return }

        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        for mutation in edit.mutations.reversed() {
            replaceCharacters(in: mutation.range, with: mutation.replacementText)
        }
        setSelectedRange(edit.resultingSelection)
        didChangeText()
    }
}
