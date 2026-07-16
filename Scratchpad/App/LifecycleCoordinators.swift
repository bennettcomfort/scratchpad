import AppKit
import SwiftUI

@MainActor
final class WindowCloseCoordinator: NSObject, NSWindowDelegate {
    private let requestClose: @MainActor () async -> Bool
    private let injectedCloseWindow: (@MainActor () -> Void)?
    private weak var window: NSWindow?
    private var closeTask: Task<Void, Never>?
    private var bypassNextClose = false

    init(
        requestClose: @escaping @MainActor () async -> Bool,
        closeWindow: (@MainActor () -> Void)? = nil
    ) {
        self.requestClose = requestClose
        self.injectedCloseWindow = closeWindow
    }

    func attach(window: NSWindow?) {
        self.window = window
    }

    func windowShouldClose() -> Bool {
        if bypassNextClose {
            bypassNextClose = false
            return true
        }
        guard closeTask == nil else { return false }

        closeTask = Task { [weak self] in
            guard let requestClose = self?.requestClose else { return }
            let approved = await requestClose()
            guard let self else { return }
            closeTask = nil
            guard approved else { return }
            bypassNextClose = true
            if let injectedCloseWindow {
                injectedCloseWindow()
            } else {
                window?.performClose(nil)
            }
            bypassNextClose = false
        }
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        windowShouldClose()
    }
}

@MainActor
private final class LifecycleWindowView: NSView {
    private let closeCoordinator: WindowCloseCoordinator

    init(model: ApplicationModel) {
        closeCoordinator = WindowCloseCoordinator(
            requestClose: { [weak model] in
                guard let model else { return false }
                return await model.requestClose()
            }
        )
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        closeCoordinator.attach(window: window)
        window?.delegate = closeCoordinator
    }
}

struct WindowLifecycleInstaller: NSViewRepresentable {
    let model: ApplicationModel

    func makeNSView(context: Context) -> NSView {
        LifecycleWindowView(model: model)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
