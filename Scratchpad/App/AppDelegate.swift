import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias TerminationRequest = @MainActor () async -> Bool
    typealias ResignActiveFlush = @MainActor (Bool) async -> Bool

    private let terminationReply: @MainActor (NSApplication, Bool) -> Void
    private var requestTermination: TerminationRequest?
    private var requestResignActiveFlush: ResignActiveFlush?
    private var presentResignActiveFailure: (@MainActor () -> Void)?
    private var terminationTask: Task<Void, Never>?
    private var resignActiveTask: Task<Void, Never>?
    private var hasPendingResignActiveFailure = false
    private var isApplicationActive = true

    override init() {
        terminationReply = { application, result in
            application.reply(toApplicationShouldTerminate: result)
        }
        super.init()
    }

    init(
        terminationReply: @escaping @MainActor (NSApplication, Bool) -> Void
    ) {
        self.terminationReply = terminationReply
        super.init()
    }

    func attach(model: ApplicationModel) {
        attachLifecycle(
            requestTermination: { [weak model] in
                guard let model else { return false }
                return await model.requestTermination()
            },
            requestResignActiveFlush: { [weak model] didCloseCleanly in
                guard let model else { return false }
                return await model.flushLifecycleState(didCloseCleanly: didCloseCleanly)
            },
            presentResignActiveFailure: { [weak model] in
                model?.presentPendingLifecycleFailure()
            }
        )
    }

    func attachLifecycle(
        requestTermination: @escaping TerminationRequest,
        requestResignActiveFlush: @escaping ResignActiveFlush,
        presentResignActiveFailure: @escaping @MainActor () -> Void
    ) {
        self.requestTermination = requestTermination
        self.requestResignActiveFlush = requestResignActiveFlush
        self.presentResignActiveFailure = presentResignActiveFailure
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let requestTermination else { return .terminateCancel }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task { [weak self] in
            let result = await requestTermination()
            guard let self else { return }
            terminationReply(sender, result)
            terminationTask = nil
        }
        return .terminateLater
    }

    func applicationDidResignActive(_ notification: Notification) {
        isApplicationActive = false
        guard resignActiveTask == nil,
              let requestResignActiveFlush else { return }

        resignActiveTask = Task { [weak self] in
            let succeeded = await requestResignActiveFlush(false)
            guard let self else { return }
            resignActiveTask = nil
            guard !succeeded else { return }
            hasPendingResignActiveFailure = true
            presentPendingResignActiveFailureIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        isApplicationActive = true
        presentPendingResignActiveFailureIfNeeded()
    }

    private func presentPendingResignActiveFailureIfNeeded() {
        guard isApplicationActive,
              hasPendingResignActiveFailure else { return }
        hasPendingResignActiveFailure = false
        presentResignActiveFailure?()
    }
}
