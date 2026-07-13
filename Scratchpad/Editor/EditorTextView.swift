import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    let buffer: OpenBuffer
    var onEdit: ((OpenBuffer) -> Void)? = nil
    var theme: EditorTheme = .scratchDark

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(buffer: buffer) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.onEdit = onEdit
        let textView = NSTextView(usingTextLayoutManager: true)
        assert(textView.textLayoutManager != nil, "TextKit 2 must be active")

        if let contentStorage = textView.textContentStorage {
            contentStorage.textStorage = buffer.storage
        }
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        apply(theme, to: textView, scroll: scroll)

        let loc = min(buffer.cursorLocation, buffer.storage.length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        apply(theme, to: textView, scroll: nsView)
    }

    private func apply(_ theme: EditorTheme, to textView: NSTextView, scroll: NSScrollView) {
        textView.font = NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: theme.leftPadding, height: theme.topPadding)
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.text)
        textView.insertionPointColor = NSColor(theme.text)
        scroll.backgroundColor = NSColor(theme.background)

        if let ts = textView.textStorage, ts.length > 0 {
            let range = NSRange(location: 0, length: ts.length)
            ts.addAttribute(.font,
                value: NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular),
                range: range)
            ts.addAttribute(.foregroundColor, value: NSColor(theme.text), range: range)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = theme.lineHeight
        textView.defaultParagraphStyle = paragraph
    }
}
