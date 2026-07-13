import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    let buffer: OpenBuffer
    let theme: EditorTheme
    var onEdit: ((OpenBuffer) -> Void)? = nil

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(buffer: buffer) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.onEdit = onEdit
        // TextKit 2 stack, explicitly. (H1: never touch .layoutManager.)
        let textView = NSTextView(usingTextLayoutManager: true)
        assert(textView.textLayoutManager != nil, "TextKit 2 must be active")

        // Bind the view to the buffer's storage — single source of truth.
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
        textView.font = theme.nsFont
        textView.textContainerInset = NSSize(width: theme.leftPadding, height: theme.topPadding)
        textView.autoresizingMask = [.width]
        textView.backgroundColor = theme.nsBackground
        textView.insertionPointColor = theme.nsText

        // Apply base text attributes to the storage.
        let fullRange = NSRange(location: 0, length: buffer.storage.length)
        buffer.storage.addAttribute(.foregroundColor, value: theme.nsText, range: fullRange)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = theme.nsBackground

        // Restore cursor if valid.
        let loc = min(buffer.cursorLocation, buffer.storage.length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.font = theme.nsFont
        textView.textContainerInset = NSSize(width: theme.leftPadding, height: theme.topPadding)
        textView.backgroundColor = theme.nsBackground
        textView.insertionPointColor = theme.nsText
        nsView.backgroundColor = theme.nsBackground
    }
}
