import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(ApplicationModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = MainWindowPresentation(
            showsInformationBar: model.settings.snapshot.showsInformationBar,
            hasErrorBanner: model.banner != nil
        )

        VStack(spacing: 0) {
            ForEach(presentation.hierarchy, id: \.self) { region in
                regionView(region)
            }
        }
        .background(
            WindowChromeConfigurator(restoredFrame: model.restoredWindowFrame)
                .frame(width: 0, height: 0)
        )
        .task(id: model.launchAttempt) {
            await model.restoreCurrentLaunchAttempt(windowFrame: currentWindowFrame)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 480, minHeight: 320)
    }

    private var theme: ThemeDefinition {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let effectiveAppearance = NSAppearance(named: appearanceName) ?? NSApp.effectiveAppearance
        return ThemeDefinition.resolve(
            model.settings.snapshot.appearance,
            effectiveAppearance: effectiveAppearance
        )
    }

    private var currentWindowFrame: CGRect {
        guard let frame = NSApp.keyWindow?.frame,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return CGRect(x: 0, y: 0, width: 820, height: 640)
        }
        return frame
    }

    private func launchFailureView(message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
            Button("Retry") {
                model.requestLaunchRetry()
            }
        }
        .padding()
    }

    private func handleBannerAction(_ action: BannerAction) {
        switch action {
        case .dismiss:
            model.banner = nil
        case .retry(let operation):
            Task { await model.retryBannerOperation(operation) }
        case .saveAs:
            Task { _ = await model.saveAs() }
        case .reselectFile:
            Task { await model.requestOpen() }
        case .openRecoveryFolder:
            openRecoveryFolder()
        }
    }

    @ViewBuilder
    private func regionView(_ region: WindowRegion) -> some View {
        switch region {
        case .titleRegion:
            DocumentTitleView(
                presentation: DocumentTitlePresentation(document: model.document),
                theme: theme
            )
            .frame(height: 44)
        case .editor:
            switch model.launchState {
            case .restoring:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                launchFailureView(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                EditorHost(
                    document: model.document,
                    settings: model.settings.snapshot,
                    onEdit: model.handleCurrentDocumentEdit,
                    onStateChange: model.handleCurrentDocumentStateChange,
                    isEditable: model.allowsDocumentEditing,
                    canEdit: { model.allowsDocumentEditing }
                )
                .id(model.document.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .errorBanner:
            if let banner = model.banner {
                ErrorBannerView(banner: banner, theme: theme) { action in
                    handleBannerAction(action)
                }
            }
        case .separator:
            Color(nsColor: theme.separator)
                .frame(height: 1)
        case .informationBar:
            InformationBarView(
                presentation: InformationBarPresentation(metrics: model.metrics),
                theme: theme
            )
            .frame(height: 28)
        }
    }

    private func openRecoveryFolder() {
        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let recoveryDirectory = applicationSupport
                .appending(path: "Scratchpad", directoryHint: .isDirectory)
                .appending(path: "recovery", directoryHint: .isDirectory)
            if !NSWorkspace.shared.open(recoveryDirectory) {
                AppLog.persistence.error("Could not open the recovery directory")
            }
        } catch {
            AppLog.persistence.error(
                "Could not locate the recovery directory: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
