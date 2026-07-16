import AppKit

@MainActor
final class ScratchTextView: NSTextView {
    var commandContext = EditorCommandContext.defaults(lineEnding: .lf)
    private var editorSettings: EditorSettingsSnapshot?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let editorSettings else { return }
        apply(style: ResolvedEditorStyle(
            settings: editorSettings,
            effectiveAppearance: effectiveAppearance
        ))
    }

    func apply(settings: EditorSettingsSnapshot) {
        editorSettings = settings
        apply(style: ResolvedEditorStyle(
            settings: settings,
            effectiveAppearance: effectiveAppearance
        ))
    }

    func apply(style: ResolvedEditorStyle) {
        font = style.font
        textColor = style.theme.editorForeground
        backgroundColor = style.theme.editorBackground
        drawsBackground = true
        insertionPointColor = style.theme.caret
        selectedTextAttributes = [
            .backgroundColor: style.theme.selection,
            .foregroundColor: style.selectionForeground,
        ]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.45
        paragraphStyle.defaultTabInterval = (" " as NSString).size(
            withAttributes: [.font: style.font]
        ).width * CGFloat(style.tabWidth)
        paragraphStyle.tabStops = []
        defaultParagraphStyle = paragraphStyle
        typingAttributes = [
            .font: style.font,
            .foregroundColor: style.theme.editorForeground,
            .paragraphStyle: paragraphStyle,
        ]

        textContainerInset = NSSize(width: 24, height: 20)
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        isAutomaticQuoteSubstitutionEnabled = style.smartSubstitutionsEnabled
        isAutomaticDashSubstitutionEnabled = style.smartSubstitutionsEnabled
        isContinuousSpellCheckingEnabled = style.spellingEnabled
        isAutomaticSpellingCorrectionEnabled = style.spellingEnabled
        commandContext = EditorCommandContext(
            lineEnding: commandContext.lineEnding,
            indentationUnit: style.insertsSpaces
                ? String(repeating: " ", count: style.tabWidth)
                : "\t",
            tabWidth: style.tabWidth,
            keepsIndentation: style.keepsIndentation
        )
    }

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
