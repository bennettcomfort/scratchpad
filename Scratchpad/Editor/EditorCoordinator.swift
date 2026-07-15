import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let documentID: UUID
    private weak var document: DocumentSession?
    private let onEdit: @MainActor (DocumentSession) -> Void

    init(
        document: DocumentSession,
        onEdit: @escaping @MainActor (DocumentSession) -> Void
    ) {
        self.documentID = document.id
        self.document = document
        self.onEdit = onEdit
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
        document.updateSelection(TextSelection(textView.selectedRange()))
    }

    @objc
    func clipViewBoundsDidChange(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView,
              let document else { return }
        document.updateScrollOffset(clipView.bounds.origin.y)
    }
}
