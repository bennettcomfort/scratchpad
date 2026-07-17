import AppKit
import Foundation
import OSLog
import SwiftUI

@main
struct ScratchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: ApplicationModel
    @State private var launchSignpostID: OSSignpostID?
    #if DEBUG
    @State private var launchStartedAt: ContinuousClock.Instant?
    @State private var launchDurationMilliseconds: Double?
    #endif
    private let applicationSupportPaths: ApplicationSupportPaths

    init() {
        #if DEBUG
        let launchStartedAt = ContinuousClock.now
        _launchStartedAt = State(initialValue: launchStartedAt)
        #endif
        let resolvedPaths = Self.resolveApplicationSupportPaths()
        applicationSupportPaths = resolvedPaths
        _launchSignpostID = State(
            initialValue: PerformanceProbe.begin(PerformanceProbe.launchToEditorReady)
        )
        #if DEBUG
        if let root = ProcessInfo.processInfo.environment["SCRATCHPAD_UI_TEST_ROOT"],
           !root.isEmpty {
            _model = State(
                initialValue: ApplicationModel.live(
                    settings: SettingsStore.transient(),
                    applicationSupportPaths: resolvedPaths
                )
            )
        } else {
            _model = State(initialValue: ApplicationModel.live())
        }
        #else
        _model = State(initialValue: ApplicationModel.live())
        #endif
    }

    private func finishLaunchProbeWhenEditorIsReady() {
        Task { @MainActor in
            for _ in 0..<1_000 {
                if NSApp.keyWindow?.firstResponder is ScratchTextView,
                   let launchSignpostID {
                    #if DEBUG
                    if let launchStartedAt {
                        let elapsed = launchStartedAt.duration(to: .now).components
                        launchDurationMilliseconds = Double(elapsed.seconds) * 1_000
                            + Double(elapsed.attoseconds) / 1_000_000_000_000_000
                        self.launchStartedAt = nil
                    }
                    #endif
                    PerformanceProbe.end(
                        PerformanceProbe.launchToEditorReady,
                        id: launchSignpostID
                    )
                    self.launchSignpostID = nil
                    return
                }
                await Task.yield()
            }
        }
    }

    private func seedPerformanceDocumentIfRequested() {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment[
            "SCRATCHPAD_UI_TEST_SEED_DOCUMENT_BYTES"
        ],
        let byteCount = Int(value),
        (1...2_000_000).contains(byteCount) else { return }

        model.document.replaceEntireContents(
            String(repeating: "a", count: byteCount),
            source: .sessionRestore,
            selection: TextSelection(location: 0, length: 0)
        )
        model.document.noteUserEdit()
        model.handleCurrentDocumentEdit(model.document)
        #endif
    }

    private static func resolveApplicationSupportPaths() -> ApplicationSupportPaths {
        #if DEBUG
        if let root = ProcessInfo.processInfo.environment["SCRATCHPAD_UI_TEST_ROOT"],
           !root.isEmpty {
            return ApplicationSupportPaths(
                root: URL(filePath: root, directoryHint: .isDirectory)
                    .appending(path: "Library", directoryHint: .isDirectory)
                    .appending(path: "Application Support", directoryHint: .isDirectory)
                    .appending(path: "Scratchpad", directoryHint: .isDirectory)
            )
        }
        #endif
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        return ApplicationSupportPaths(
            root: applicationSupport.appending(path: "Scratchpad", directoryHint: .isDirectory)
        )
    }

    var body: some Scene {
        Window("Untitled", id: "main") {
            MainWindowView()
                .environment(model)
                .overlay(alignment: .topLeading) {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["SCRATCHPAD_UI_TEST_ROOT"] != nil,
                       let launchDurationMilliseconds {
                        Text("Launch duration")
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .accessibilityIdentifier("launch-duration")
                            .accessibilityValue(
                                String(format: "%.3f", launchDurationMilliseconds)
                            )
                    }
                    #endif
                }
                .background(WindowLifecycleInstaller(model: model))
                .onAppear { appDelegate.attach(model: model) }
                .onChange(of: model.launchState) { _, launchState in
                    guard launchState == .ready else { return }
                    finishLaunchProbeWhenEditorIsReady()
                    seedPerformanceDocumentIfRequested()
                }
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
        .commands {
            TextEditingCommands()
            AppCommands(model: model)
            SettingsTabCommands()
        }

        Settings {
            SettingsView(
                settings: model.settings,
                recoveryFolder: applicationSupportPaths.recoveryDirectory
            )
        }
    }
}

private struct SettingsTabCommands: Commands {
    @FocusedBinding(\.settingsTabSelection) private var selectedTab

    var body: some Commands {
        CommandMenu("Settings Tabs") {
            Button("General") { selectedTab = .general }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(selectedTab == nil)
            Button("Editor") { selectedTab = .editor }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(selectedTab == nil)
            Button("Theme") { selectedTab = .theme }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(selectedTab == nil)
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
                        .keyboardShortcut(.cancelAction)
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
                        .keyboardShortcut(.cancelAction)
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
                        .keyboardShortcut(.cancelAction)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decision-sheet")
    }
}
