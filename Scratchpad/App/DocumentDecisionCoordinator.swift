import Foundation
import Observation

struct ErrorBanner: Identifiable, Equatable {
    let id: UUID
    let message: String
    let actions: [BannerAction]
}

enum BannerAction: Equatable {
    case dismiss
    case retry
    case saveAs
    case reselectFile
    case openRecoveryFolder
}

enum PendingReplacement: Equatable, Sendable {
    case newUntitled
    case open(ExternalFileReference)
}

struct ConflictContext: Equatable, Sendable {
    let documentID: UUID
    let initiatingGeneration: Int
    let fileReference: ExternalFileReference
    let baseHash: String?
    let diskHash: String
    let diskModificationDate: Date
}

enum DocumentDecision {
    case replaceCurrentDocument(PendingReplacement)
    case closeWindow
    case terminateApplication
    case resolveConflict(ConflictContext)
    case recreateDeletedFile
}

enum DocumentDecisionResolution: Equatable {
    case save
    case discard
    case cancel
    case overwrite
    case reloadFromDisk
    case saveAs
    case recreate
}

@MainActor
@Observable
final class DocumentDecisionCoordinator {
    private(set) var pending: DocumentDecision?

    @ObservationIgnored
    private let onBegin: @MainActor (DocumentDecision) -> Void
    @ObservationIgnored
    private var continuation: CheckedContinuation<DocumentDecisionResolution, Never>?
    @ObservationIgnored
    private var queuedResolution: DocumentDecisionResolution?

    init(onBegin: @escaping @MainActor (DocumentDecision) -> Void = { _ in }) {
        self.onBegin = onBegin
    }

    func request(_ decision: DocumentDecision) async -> DocumentDecisionResolution {
        guard begin(decision) else { return .cancel }
        return await waitForResolution()
    }

    func begin(_ decision: DocumentDecision) -> Bool {
        guard pending == nil,
              continuation == nil,
              queuedResolution == nil else { return false }
        onBegin(decision)
        pending = decision
        return true
    }

    func waitForResolution() async -> DocumentDecisionResolution {
        guard pending != nil else { return .cancel }
        if let queuedResolution {
            pending = nil
            self.queuedResolution = nil
            return queuedResolution
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolvePending(with resolution: DocumentDecisionResolution) {
        guard pending != nil else { return }
        guard let continuation else {
            queuedResolution = resolution
            return
        }
        pending = nil
        self.continuation = nil
        continuation.resume(returning: resolution)
    }

    func cancelPending() {
        guard pending != nil else { return }
        pending = nil
        queuedResolution = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: .cancel)
    }
}
