import Observation

@MainActor
@Observable
final class ApplicationModel {
    private(set) var document: DocumentSession

    init(document: DocumentSession = DocumentSession()) {
        self.document = document
    }
}
