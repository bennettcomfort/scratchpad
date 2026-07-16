import SwiftUI

@main
struct ScratchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ApplicationModel.live()
    private let applicationSupportPaths: ApplicationSupportPaths

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        applicationSupportPaths = ApplicationSupportPaths(
            root: applicationSupport.appending(path: "Scratchpad", directoryHint: .isDirectory)
        )
    }

    var body: some Scene {
        Window("Untitled", id: "main") {
            MainWindowView()
                .environment(model)
                .background(WindowLifecycleInstaller(model: model))
                .onAppear { appDelegate.attach(model: model) }
                .sheet(
                    isPresented: Binding(
                        get: { model.pendingDecision != nil },
                        set: { isPresented in
                            if !isPresented, model.pendingDecision != nil {
                                model.resolvePendingDecision(with: .cancel)
                            }
                        }
                    )
                ) {
                    DocumentDecisionSheet(decision: model.pendingDecision) { resolution in
                        model.resolvePendingDecision(with: resolution)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 820, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            TextEditingCommands()
            AppCommands(model: model)
        }

        Settings {
            SettingsView(
                settings: model.settings,
                recoveryFolder: applicationSupportPaths.recoveryDirectory
            )
        }
    }
}

private struct DocumentDecisionSheet: View {
    let decision: DocumentDecision?
    let resolve: (DocumentDecisionResolution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch decision {
            case .replaceCurrentDocument, .closeWindow, .terminateApplication:
                Text("Save your changes?")
                    .font(.headline)
                Text("Your changes must be saved or discarded before continuing.")
                HStack {
                    Button("Cancel", role: .cancel) { resolve(.cancel) }
                    Spacer()
                    Button("Discard", role: .destructive) { resolve(.discard) }
                    Button("Save") { resolve(.save) }
                        .keyboardShortcut(.defaultAction)
                }
            case .resolveConflict:
                Text("The file changed on disk")
                    .font(.headline)
                Text("Choose which version to keep, or save your edits to another file.")
                HStack {
                    Button("Cancel", role: .cancel) { resolve(.cancel) }
                    Spacer()
                    Button("Reload") { resolve(.reloadFromDisk) }
                    Button("Save As") { resolve(.saveAs) }
                    Button("Overwrite", role: .destructive) { resolve(.overwrite) }
                }
            case .recreateDeletedFile:
                Text("The file was deleted")
                    .font(.headline)
                Text("Recreate it using the current document contents?")
                HStack {
                    Button("Cancel", role: .cancel) { resolve(.cancel) }
                    Spacer()
                    Button("Recreate", role: .destructive) { resolve(.recreate) }
                        .keyboardShortcut(.defaultAction)
                }
            case nil:
                EmptyView()
            }
        }
        .padding(20)
        .frame(minWidth: 440)
    }
}
