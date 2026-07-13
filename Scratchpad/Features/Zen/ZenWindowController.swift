import AppKit
import SwiftUI

@MainActor
final class ZenWindowController {
    private let model: AppModel
    private var window: NSWindow?
    private var currentBuffer: OpenBuffer?
    static let defaultSize = CGSize(width: 640, height: 400)

    init(model: AppModel) { self.model = model }

    func summon() {
        let buffer = model.bufferStore.createScratchBuffer()
        currentBuffer = buffer
        model.sessionService.noteStructuralChange()

        let win = window ?? makeWindow()
        window = win

        let size = win.frame.size == .zero ? Self.defaultSize : win.frame.size
        let frame = ScreenPlacement.targetFrame(
            mouse: NSEvent.mouseLocation,
            screens: NSScreen.screens.map(\.frame),
            windowSize: size)

        win.contentView = NSHostingView(rootView:
            ZenContainerView(buffer: buffer, controller: self)
                .environment(model))
        win.setFrame(frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
        win.makeFirstResponder(win.contentView)
    }

    func dismiss(copyToClipboard: Bool) {
        if copyToClipboard, let text = currentBuffer?.text, !text.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
        window?.orderOut(nil)
        model.sessionService.noteStructuralChange()
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered, defer: false)
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("ZenWindow")
        return win
    }
}

struct ZenContainerView: View {
    let buffer: OpenBuffer
    let controller: ZenWindowController
    @Environment(AppModel.self) private var model

    var body: some View {
        EditorTextView(buffer: buffer,
                       theme: model.themeManager.current,
                       onEdit: { model.sessionService.noteBufferEdited($0) })
            .background(KeyCatcher(
                onCommandReturn: { controller.dismiss(copyToClipboard: true) },
                onEscape: {
                    let alsoCopy = UserDefaults.standard.bool(forKey: "escAlsoCopies")
                    controller.dismiss(copyToClipboard: alsoCopy)
                }))
    }
}

struct KeyCatcher: NSViewRepresentable {
    let onCommandReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyCatcherView()
        v.onCommandReturn = onCommandReturn
        v.onEscape = onEscape
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyCatcherView: NSView {
        var onCommandReturn: (() -> Void)?
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { false }
        override func viewDidMoveToWindow() {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if event.keyCode == 36, event.modifierFlags.contains(.command) {
                    self.onCommandReturn?(); return nil
                }
                if event.keyCode == 53 {
                    self.onEscape?(); return nil
                }
                return event
            }
        }
    }
}
