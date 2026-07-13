import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    let buffer: OpenBuffer

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator(buffer: buffer) }

    func makeNSView(context: Context) -> NSScrollView {
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
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true

        // Restore cursor if valid.
        let loc = min(buffer.cursorLocation, buffer.storage.length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Intentionally empty for text: storage IS the source of truth.
        // Theme/font updates arrive here in Stage 10.
    }
}
