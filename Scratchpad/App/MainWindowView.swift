import SwiftUI

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let showQuickSwitcher = Notification.Name("showQuickSwitcher")
}

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebarVisible = false
    @State private var showQuickSwitcher = false

    private var theme: EditorTheme { model.themeManager.current }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()

            HStack(spacing: 0) {
                if sidebarVisible {
                    SidebarView()
                }

                VStack(spacing: 0) {
                    if let id = model.bufferStore.activeBufferID,
                       let buffer = model.bufferStore.buffer(id: id) {
                        EditorTextView(
                            buffer: buffer,
                            theme: theme,
                            onEdit: { model.sessionService.noteBufferEdited($0) })
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(theme.background)
        .overlay {
            if showQuickSwitcher {
                theme.background.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { showQuickSwitcher = false }
                QuickSwitcherView()
            }
        }
        .onAppear {
            syncWindow()
            Task {
                await model.sessionService.restoreOnLaunch()
                model.startGlobalHotkey()
            }
        }
        .onChange(of: theme.name) { _, _ in syncWindow() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation { sidebarVisible.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showQuickSwitcher)) { _ in
            showQuickSwitcher = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissQuickSwitcher)) { _ in
            showQuickSwitcher = false
        }
    }

    private func syncWindow() {
        guard let window = NSApp.mainWindow else { return }
        window.titlebarAppearsTransparent = true
        window.backgroundColor = theme.nsBackground
        window.isOpaque = true
        window.hasShadow = true
    }
}
