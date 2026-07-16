import Foundation

@MainActor
final class MetricsCoordinator {
    private let delay: Duration
    private var scheduledToken: UUID?

    init(delay: Duration = .milliseconds(75)) {
        self.delay = delay
    }

    func schedule(
        documentID: UUID,
        generation: Int,
        text: String,
        countsWhitespace: Bool,
        deliver: @escaping @MainActor (UUID, Int, DocumentMetrics) -> Void
    ) {
        let token = UUID()
        scheduledToken = token
        let delay = delay

        Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, self.scheduledToken == token else { return }

            let metrics = await Task.detached(priority: .utility) {
                DocumentMetricsCalculator.calculate(
                    text: text,
                    countsWhitespace: countsWhitespace
                )
            }.value

            guard self.scheduledToken == token else { return }
            self.scheduledToken = nil
            deliver(documentID, generation, metrics)
        }
    }

    func cancel() {
        scheduledToken = nil
    }
}
