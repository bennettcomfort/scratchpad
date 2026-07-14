import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("editorFontSize") private var fontSize = 14.0
    @AppStorage("editorFontFamily") private var fontFamily = ""
    @AppStorage("sidebarVisible") private var sidebarVisible = false
    @AppStorage("showQuickSwitcher") private var showQuickSwitcher = false

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
                            fontSize: fontSize,
                            fontFamily: fontFamily,
                            onEdit: { model.sessionService.noteBufferEdited($0) })
                        Divider()
                    } else {
                        Color.clear
                    }
                    StatusBarView()
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
    }

    private func syncWindow() {
        guard let window = NSApp.mainWindow else { return }
        window.titlebarAppearsTransparent = true
        window.backgroundColor = theme.nsBackground
        window.isOpaque = true
        window.hasShadow = true
    }
}
