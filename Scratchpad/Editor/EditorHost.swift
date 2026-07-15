import AppKit
import SwiftUI

@MainActor
struct EditorHost: NSViewRepresentable {
    let document: DocumentSession
    var onEdit: @MainActor (DocumentSession) -> Void = { _ in }

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(document: document, onEdit: onEdit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        Self.makeScrollView(document: document, coordinator: context.coordinator)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        precondition(context.coordinator.documentID == document.id)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            preconditionFailure("EditorHost lost its ScratchTextView")
        }
        precondition(textView.textLayoutManager != nil)
        precondition(textView.textStorage === document.storage)
        textView.commandContext = .defaults(lineEnding: document.lineEnding)
    }

    static func dismantleNSView(
        _ scrollView: NSScrollView,
        coordinator: EditorCoordinator
    ) {
        coordinator.detach()
        if let textView = scrollView.documentView as? ScratchTextView {
            textView.delegate = nil
        }
    }

    static func makeScrollView(
        document: DocumentSession,
        coordinator: EditorCoordinator
    ) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = ScratchTextView(usingTextLayoutManager: true)
        textView.commandContext = .defaults(lineEnding: document.lineEnding)
        guard let contentStorage = textView.textContentStorage else {
            preconditionFailure("TextKit 2 content storage is unavailable")
        }
        guard let textContainer = textView.textContainer else {
            preconditionFailure("TextKit 2 text container is unavailable")
        }

        contentStorage.textStorage = document.storage
        precondition(textView.textLayoutManager != nil)
        precondition(textView.textStorage === document.storage)

        coordinator.attach(to: scrollView, textView: textView)
        textView.setSelectedRange(document.selection.nsRange)
        scrollView.contentView.scroll(
            to: NSPoint(x: 0, y: document.scrollOffsetY)
        )
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.frame = scrollView.contentView.bounds
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }
}
