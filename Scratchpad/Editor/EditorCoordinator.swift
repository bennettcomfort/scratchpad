import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let documentID: UUID
    private weak var document: DocumentSession?
    private let onEdit: @MainActor (DocumentSession) -> Void
    private let onStateChange: @MainActor (DocumentSession) -> Void

    init(
        document: DocumentSession,
        onEdit: @escaping @MainActor (DocumentSession) -> Void,
        onStateChange: @escaping @MainActor (DocumentSession) -> Void = { _ in }
    ) {
        self.documentID = document.id
        self.document = document
        self.onEdit = onEdit
        self.onStateChange = onStateChange
    }

    func attach(to scrollView: NSScrollView, textView: ScratchTextView) {
        textView.delegate = self
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    func detach() {
        NotificationCenter.default.removeObserver(self)
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let document,
              textView.textStorage === document.storage else { return }

        document.updateSelection(TextSelection(textView.selectedRange()))
        guard !document.isPerformingWholeTextReplacement else { return }
        document.noteUserEdit()
        onEdit(document)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              let document,
              textView.textStorage === document.storage else { return }
        let previousSelection = document.selection
        document.updateSelection(TextSelection(textView.selectedRange()))
        if document.selection != previousSelection {
            onStateChange(document)
        }
    }

    @objc
    func clipViewBoundsDidChange(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView,
              let document else { return }
        let previousOffset = document.scrollOffsetY
        document.updateScrollOffset(clipView.bounds.origin.y)
        if document.scrollOffsetY != previousOffset {
            onStateChange(document)
        }
    }
}
