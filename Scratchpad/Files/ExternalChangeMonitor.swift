import Foundation

@MainActor
final class ExternalChangeMonitor {
    private let fileService: any FileServicing
    private let clock: any RecoveryClock
    private var task: Task<Void, Never>?

    init(fileService: any FileServicing, clock: any RecoveryClock) {
        self.fileService = fileService
        self.clock = clock
    }

    func start(
        document: DocumentSession,
        deliver: @escaping @MainActor (UUID, Int, ExternalFileStatus) async -> Void
    ) {
        stop()
        guard document.fileReference != nil else { return }

        let documentID = document.id
        let initialSnapshot = document.snapshot()
        let fileService = fileService
        let clock = clock
        task = Task { @MainActor [weak document] in
            var snapshot = initialSnapshot
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .seconds(1))
                    try Task.checkCancellation()
                    let status = try await fileService.inspect(snapshot)
                    try Task.checkCancellation()
                    await deliver(documentID, snapshot.generation, status)
                } catch is CancellationError {
                    return
                } catch {
                    // A transient inspection failure must not mutate the document.
                }

                guard !Task.isCancelled,
                      let document,
                      document.id == documentID else { return }
                snapshot = document.snapshot()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
