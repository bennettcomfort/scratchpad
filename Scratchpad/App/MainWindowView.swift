import SwiftUI

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let showQuickSwitcher = Notification.Name("showQuickSwitcher")
}

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebarVisible = false
    @State private var showQuickSwitcher = false

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
                            theme: model.themeManager.current,
                            onEdit: { model.sessionService.noteBufferEdited($0) })
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .overlay {
            if showQuickSwitcher {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { showQuickSwitcher = false }
                QuickSwitcherView()
            }
        }
        .onAppear {
            Task {
                await model.sessionService.restoreOnLaunch()
                model.startGlobalHotkey()
            }
        }
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
}
