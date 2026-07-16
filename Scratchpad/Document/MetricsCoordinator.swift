import Foundation

@MainActor
final class MetricsCoordinator {
    private let delay: Duration
    private var scheduledToken: UUID?
    private var scheduledTask: Task<Void, Never>?
    private let calculationDidStart: @MainActor () -> Void
    private let workDidEnd: @MainActor () -> Void

    init(delay: Duration = .milliseconds(75)) {
        self.delay = delay
        self.calculationDidStart = {}
        self.workDidEnd = {}
    }

    init(
        delay: Duration,
        calculationDidStart: @escaping @MainActor () -> Void,
        workDidEnd: @escaping @MainActor () -> Void
    ) {
        self.delay = delay
        self.calculationDidStart = calculationDidStart
        self.workDidEnd = workDidEnd
    }

    func schedule(
        documentID: UUID,
        generation: Int,
        text: String,
        countsWhitespace: Bool,
        deliver: @escaping @MainActor (UUID, Int, DocumentMetrics) -> Void
    ) {
        cancel()
        let token = UUID()
        scheduledToken = token
        let delay = delay

        scheduledTask = Task { [weak self] in
            defer { self?.finishWork(token: token) }
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            } catch {
                return
            }
            guard let self, self.scheduledToken == token else { return }
            self.calculationDidStart()
            guard !Task.isCancelled else { return }

            let calculation = Task.detached(priority: .utility) {
                DocumentMetricsCalculator.calculateUnlessCancelled(
                    text: text,
                    countsWhitespace: countsWhitespace
                )
            }
            let metrics = await withTaskCancellationHandler {
                await calculation.value
            } onCancel: {
                calculation.cancel()
            }

            guard !Task.isCancelled,
                  let metrics,
                  self.scheduledToken == token else { return }
            self.scheduledToken = nil
            self.scheduledTask = nil
            deliver(documentID, generation, metrics)
        }
    }

    func cancel() {
        scheduledToken = nil
        let task = scheduledTask
        scheduledTask = nil
        task?.cancel()
    }

    private func finishWork(token: UUID) {
        if scheduledToken == token {
            scheduledToken = nil
            scheduledTask = nil
        }
        workDidEnd()
    }
}
