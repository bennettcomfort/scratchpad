import Foundation

@MainActor
final class Debouncer {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration) { self.delay = delay }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
