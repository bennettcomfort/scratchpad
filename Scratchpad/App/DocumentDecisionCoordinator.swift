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
    private var continuation: CheckedContinuation<DocumentDecisionResolution, Never>?

    func request(_ decision: DocumentDecision) async -> DocumentDecisionResolution {
        guard pending == nil, continuation == nil else { return .cancel }
        return await withCheckedContinuation { continuation in
            pending = decision
            self.continuation = continuation
        }
    }

    func resolvePending(with resolution: DocumentDecisionResolution) {
        guard pending != nil, let continuation else { return }
        pending = nil
        self.continuation = nil
        continuation.resume(returning: resolution)
    }
}
