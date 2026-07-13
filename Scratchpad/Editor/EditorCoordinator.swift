import AppKit

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let buffer: OpenBuffer
    init(buffer: OpenBuffer) { self.buffer = buffer }

    func textDidChange(_ notification: Notification) {
        buffer.noteEdited()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        buffer.cursorLocation = tv.selectedRange().location
    }
}
