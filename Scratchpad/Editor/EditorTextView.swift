import SwiftUI
import AppKit

struct EditorTextView: NSViewRepresentable {
    let buffer: OpenBuffer
    let theme: EditorTheme
    let fontSize: CGFloat
    let fontFamily: String
    var onEdit: ((OpenBuffer) -> Void)? = nil

    private var resolvedFont: NSFont {
        let size = fontSize
        if !fontFamily.isEmpty {
            let descriptor = NSFontDescriptor(fontAttributes: [.family: fontFamily])
            if let font = NSFont(descriptor: descriptor, size: CGFloat(size)) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

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
        textView.font = resolvedFont
        textView.textContainerInset = NSSize(width: theme.leftPadding, height: theme.topPadding)
        textView.autoresizingMask = [.width]
        textView.backgroundColor = theme.nsBackground
        textView.textColor = theme.nsText
        textView.insertionPointColor = theme.nsText
        textView.drawsBackground = true

        // Set typing attributes so newly typed text uses the theme color.
        textView.typingAttributes = [
            .font: resolvedFont,
            .foregroundColor: theme.nsText
        ]

        // Apply base text attributes to the storage.
        let fullRange = NSRange(location: 0, length: buffer.storage.length)
        if fullRange.length > 0 {
            buffer.storage.addAttribute(.foregroundColor, value: theme.nsText, range: fullRange)
        }

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = theme.nsBackground

        // Restore cursor if valid.
        let loc = min(buffer.cursorLocation, buffer.storage.length)
        textView.setSelectedRange(NSRange(location: loc, length: 0))

        context.coordinator.setupEventMonitor(for: textView)
        return scroll
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: EditorCoordinator) {
        coordinator.removeEventMonitor()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let newFont = resolvedFont
        let fontChanged = textView.font?.pointSize != newFont.pointSize ||
                          textView.font?.familyName != newFont.familyName

        textView.font = newFont
        textView.textContainerInset = NSSize(width: theme.leftPadding, height: theme.topPadding)
        textView.backgroundColor = theme.nsBackground
        textView.textColor = theme.nsText
        textView.insertionPointColor = theme.nsText
        textView.drawsBackground = true
        textView.typingAttributes = [
            .font: newFont,
            .foregroundColor: theme.nsText
        ]
        // Re-apply foreground color to existing text when theme changes.
        let fullRange = NSRange(location: 0, length: buffer.storage.length)
        if fullRange.length > 0 {
            buffer.storage.addAttribute(.foregroundColor, value: theme.nsText, range: fullRange)
        }
        // Re-highlight when font changes so token fonts match.
        if fontChanged, fullRange.length > 0, fullRange.length < 2_000_000 {
            let tokens = MarkdownTokenizer.tokenize(buffer.storage.string)
            HighlightApplier.apply(tokens, to: buffer.storage, font: newFont, textColor: theme.nsText)
        }
        nsView.backgroundColor = theme.nsBackground
    }
}
