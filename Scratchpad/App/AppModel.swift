import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let bufferStore = BufferStore()
    let sessionService: SessionService
    private let sessionWriter: SessionWriter
    private(set) var zenController: ZenWindowController?
    private let hotkeyManager = HotkeyManager()

    init() {
        let paths = (try? ApplicationSupportPaths.standard())
            ?? ApplicationSupportPaths(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("Scratchpad-fallback"))
        let writer = SessionWriter(paths: paths)
        self.sessionWriter = writer
        self.sessionService = SessionService(bufferStore: bufferStore, writer: writer)

        let closedCleanly = UserDefaults.standard.bool(forKey: "didCloseCleanly")
        UserDefaults.standard.set(false, forKey: "didCloseCleanly")
        if !closedCleanly {
            Log.logger("session").notice("previous run did not close cleanly")
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            UserDefaults.standard.set(true, forKey: "didCloseCleanly")
            self?.sessionService.noteStructuralChange()
        }

        self.zenController = ZenWindowController(model: self)
    }

    func newScratchBuffer() {
        bufferStore.createScratchBuffer()
        sessionService.noteStructuralChange()
    }

    func startGlobalHotkey() {
        hotkeyManager.register { [weak self] in self?.zenController?.summon() }
    }
}
