import AppKit
import SwiftUI

enum WindowRegion: CaseIterable, Equatable, Hashable {
    case titleRegion
    case editor
    case errorBanner
    case separator
    case informationBar
}

struct MainWindowPresentation: Equatable {
    let titleRegionHeight: CGFloat = 44
    let separatorHeight: CGFloat = 1
    let informationBarHeight: CGFloat
    let hierarchy: [WindowRegion]

    var fixedHeight: CGFloat {
        titleRegionHeight + separatorHeight + informationBarHeight
    }

    init(showsInformationBar: Bool, hasErrorBanner: Bool) {
        informationBarHeight = showsInformationBar ? 28 : 0
        var regions: [WindowRegion] = [.titleRegion, .editor]
        if hasErrorBanner {
            regions.append(.errorBanner)
        }
        regions.append(.separator)
        if showsInformationBar {
            regions.append(.informationBar)
        }
        hierarchy = regions
    }
}

enum WindowChromeConfiguration {
    static let defaultSize = NSSize(width: 820, height: 640)
    static let minimumSize = NSSize(width: 480, height: 320)

    static func targetFrame(
        restoredFrame: NSRect?,
        currentScreenFrames: [NSRect]
    ) -> NSRect {
        if let restoredFrame,
           isValid(restoredFrame),
           currentScreenFrames.contains(where: { !$0.intersection(restoredFrame).isEmpty }) {
            return restoredFrame
        }

        guard let screenFrame = currentScreenFrames.first,
              isValid(screenFrame) else {
            return NSRect(origin: .zero, size: defaultSize)
        }
        return NSRect(
            x: screenFrame.midX - defaultSize.width / 2,
            y: screenFrame.midY - defaultSize.height / 2,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }

    private static func isValid(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}

@MainActor
struct WindowChromeConfigurator: NSViewRepresentable {
    let restoredFrame: CGRect?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowChange = { window in
            context.coordinator.configure(window, restoredFrame: restoredFrame)
        }
        return view
    }

    func updateNSView(_ view: WindowAttachmentView, context: Context) {
        view.onWindowChange = { window in
            context.coordinator.configure(window, restoredFrame: restoredFrame)
        }
        if let window = view.window {
            context.coordinator.configure(window, restoredFrame: restoredFrame)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var configuredWindow: NSWindow?
        private var appliedFrame = false
        private var appliedRestoredFrame: CGRect?

        func configure(_ window: NSWindow, restoredFrame: CGRect?) {
            if configuredWindow !== window {
                configuredWindow = window
                appliedFrame = false
                appliedRestoredFrame = nil
            }

            window.contentMinSize = WindowChromeConfiguration.minimumSize
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true

            guard !appliedFrame || restoredFrame != appliedRestoredFrame else { return }
            var screenFrames: [NSRect] = window.screen.map { [$0.visibleFrame] } ?? []
            screenFrames.append(contentsOf: NSScreen.screens.map(\.visibleFrame).filter {
                !screenFrames.contains($0)
            })
            let frame = WindowChromeConfiguration.targetFrame(
                restoredFrame: restoredFrame,
                currentScreenFrames: screenFrames
            )
            window.setFrame(frame, display: true)
            appliedFrame = true
            appliedRestoredFrame = restoredFrame
        }
    }
}

@MainActor
final class WindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowChange?(window)
        }
    }
}
