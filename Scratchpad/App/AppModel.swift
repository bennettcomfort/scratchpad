import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let bufferStore = BufferStore()
    let sessionService: SessionService
    private let sessionWriter: SessionWriter
    let bookmarkManager: BookmarkManager
    let workspace: WorkspaceModel
    let themeManager = ThemeManager()
    private(set) var fileService: FileService!
    private let fileWatcher = FileWatcher()
    private(set) var zenController: ZenWindowController?
    private let hotkeyManager = HotkeyManager()

    init() {
        let paths = (try? ApplicationSupportPaths.standard())
            ?? ApplicationSupportPaths(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("Scratchpad-fallback"))
        let writer = SessionWriter(paths: paths)
        self.sessionWriter = writer
        self.sessionService = SessionService(bufferStore: bufferStore, writer: writer)

        let bm = BookmarkManager()
        self.bookmarkManager = bm
        self.workspace = WorkspaceModel(bookmarkManager: bm)

        let closedCleanly = UserDefaults.standard.bool(forKey: "didCloseCleanly")
        UserDefaults.standard.set(false, forKey: "didCloseCleanly")
        if !closedCleanly {
            Log.logger("session").notice("previous run did not close cleanly")
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            UserDefaults.standard.set(true, forKey: "didCloseCleanly")
            Task { @MainActor in self?.sessionService.noteStructuralChange() }
        }

        self.zenController = ZenWindowController(model: self)
        self.fileService = FileService(bookmarkManager: bookmarkManager, sessionWriter: writer, bufferStore: bufferStore)
        Task { await fileWatcher.start(watching: self.fileService) }
    }

    func newScratchBuffer() {
        bufferStore.createScratchBuffer()
        sessionService.noteStructuralChange()
    }

    func startGlobalHotkey() {
        hotkeyManager.register { [weak self] in self?.zenController?.summon() }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .data, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    let (text, mtime, hash) = try await self.fileService.open(url: url)
                    try await self.bookmarkManager.saveBookmark(for: url)
                    let buffer = OpenBuffer(fileURL: url, displayName: url.deletingPathExtension().lastPathComponent)
                    buffer.replaceEntireContents(text)
                    buffer.lastKnownDiskMTime = mtime
                    buffer.lastSavedHash = hash
                    self.bufferStore.adopt(buffer)
                    self.sessionService.noteStructuralChange()
                } catch {
                    Log.logger("file").error("Open failed: \(error, privacy: .public)")
                }
            }
        }
    }

    func saveFile() {
        guard let id = bufferStore.activeBufferID,
              let buffer = bufferStore.buffer(id: id),
              buffer.fileURL != nil else { return }
        Task {
            do {
                try await fileService.save(buffer: buffer)
            } catch {
                Log.logger("file").error("Save failed: \(error, privacy: .public)")
            }
        }
    }

    func saveFileAs() {
        guard let id = bufferStore.activeBufferID,
              let buffer = bufferStore.buffer(id: id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        if let existing = buffer.fileURL {
            panel.directoryURL = existing.deletingLastPathComponent()
            panel.nameFieldStringValue = existing.lastPathComponent
        } else {
            panel.nameFieldStringValue = buffer.displayName + ".txt"
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    try await self.fileService.saveAs(buffer: buffer, to: url)
                    self.sessionService.noteStructuralChange()
                } catch {
                    Log.logger("file").error("Save As failed: \(error, privacy: .public)")
                }
            }
        }
    }

    func closeActiveTab() {
        guard let id = bufferStore.activeBufferID,
              let buffer = bufferStore.buffer(id: id) else { return }
        if buffer.saveState == .dirty, buffer.fileURL != nil {
            let alert = NSAlert()
            alert.messageText = "Do you want to save changes to \"\(buffer.displayName)\"?"
            alert.informativeText = "Your changes will be lost if you don't save."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard")
            alert.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:
                    Task {
                        do { try await self.fileService.save(buffer: buffer) }
                        catch { Log.logger("file").error("Save failed on close: \(error, privacy: .public)") }
                    }
                    fallthrough
                case .alertThirdButtonReturn:
                    self.bufferStore.close(id: id)
                    self.sessionService.noteStructuralChange()
                default: break
                }
            }
        } else {
            bufferStore.close(id: id)
            sessionService.noteStructuralChange()
        }
    }

    func nextTab() {
        guard let id = bufferStore.activeBufferID,
              let idx = bufferStore.buffers.firstIndex(where: { $0.id == id }) else { return }
        let next = (idx + 1) % bufferStore.buffers.count
        bufferStore.activeBufferID = bufferStore.buffers[next].id
    }

    func previousTab() {
        guard let id = bufferStore.activeBufferID,
              let idx = bufferStore.buffers.firstIndex(where: { $0.id == id }) else { return }
        let prev = (idx - 1 + bufferStore.buffers.count) % bufferStore.buffers.count
        bufferStore.activeBufferID = bufferStore.buffers[prev].id
    }

    func openFolder() {
        workspace.openFolder()
    }

    func openWorkspaceFile(_ url: URL) {
        // Check if already open — if so, switch to it.
        if let existing = bufferStore.buffers.first(where: { $0.fileURL == url }) {
            bufferStore.activeBufferID = existing.id
            return
        }
        Task {
            do {
                let (text, mtime, hash) = try await fileService.open(url: url)
                let buffer = OpenBuffer(fileURL: url, displayName: url.deletingPathExtension().lastPathComponent)
                buffer.replaceEntireContents(text)
                buffer.lastKnownDiskMTime = mtime
                buffer.lastSavedHash = hash
                bufferStore.adopt(buffer)
                sessionService.noteStructuralChange()
            } catch {
                Log.logger("file").error("Workspace open failed: \(error, privacy: .public)")
            }
        }
    }
}
