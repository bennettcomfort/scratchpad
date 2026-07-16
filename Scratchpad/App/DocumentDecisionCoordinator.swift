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
    private struct ResolutionWaiter {
        let id: UUID
        let continuation: CheckedContinuation<DocumentDecisionResolution, Never>
    }

    private(set) var pending: DocumentDecision?

    @ObservationIgnored
    private let onBegin: @MainActor (DocumentDecision) -> Void
    @ObservationIgnored
    private var waiter: ResolutionWaiter?
    @ObservationIgnored
    private var queuedResolution: DocumentDecisionResolution?

    var hasActiveWaiter: Bool { waiter != nil }

    init(onBegin: @escaping @MainActor (DocumentDecision) -> Void = { _ in }) {
        self.onBegin = onBegin
    }

    func request(_ decision: DocumentDecision) async -> DocumentDecisionResolution {
        guard begin(decision) else { return .cancel }
        return await waitForResolution()
    }

    func begin(_ decision: DocumentDecision) -> Bool {
        guard pending == nil,
              waiter == nil,
              queuedResolution == nil else { return false }
        pending = decision
        onBegin(decision)
        return true
    }

    func waitForResolution() async -> DocumentDecisionResolution {
        guard pending != nil,
              waiter == nil else { return .cancel }
        guard !Task.isCancelled else {
            cancelPending()
            return .cancel
        }
        if let queuedResolution {
            pending = nil
            self.queuedResolution = nil
            return queuedResolution
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard pending != nil,
                      waiter == nil else {
                    continuation.resume(returning: .cancel)
                    return
                }
                waiter = ResolutionWaiter(id: waiterID, continuation: continuation)
                if Task.isCancelled {
                    cancelWaiter(id: waiterID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(id: waiterID)
            }
        }
    }

    func resolvePending(with resolution: DocumentDecisionResolution) {
        guard pending != nil else { return }
        guard let waiter else {
            if queuedResolution == nil {
                queuedResolution = resolution
            }
            return
        }
        pending = nil
        queuedResolution = nil
        self.waiter = nil
        waiter.continuation.resume(returning: resolution)
    }

    func cancelPending() {
        guard pending != nil else { return }
        pending = nil
        queuedResolution = nil
        let waiter = waiter
        self.waiter = nil
        waiter?.continuation.resume(returning: .cancel)
    }

    private func cancelWaiter(id: UUID) {
        guard waiter?.id == id else { return }
        cancelPending()
    }
}
