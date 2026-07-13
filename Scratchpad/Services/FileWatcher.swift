import Foundation

actor FileWatcher {
    private var task: Task<Void, Never>?
    private var fileService: FileService?
    private let log = Log.logger("file-watcher")

    init() {}

    func start(watching service: FileService) {
        self.fileService = service
        task?.cancel()
        task = Task { [service] in
            while !Task.isCancelled {
                await service.pollExternalChanges()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        fileService = nil
    }
}
