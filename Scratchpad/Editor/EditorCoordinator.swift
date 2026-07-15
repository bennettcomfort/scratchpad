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
}
