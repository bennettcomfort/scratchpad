import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(ApplicationModel.self) private var model

    var body: some View {
        Group {
            switch model.launchState {
            case .restoring:
                ProgressView()
            case .failed(let message):
                launchFailureView(message: message)
            case .ready:
                EditorHost(
                    document: model.document,
                    onEdit: model.handleCurrentDocumentEdit
                )
                    .id(model.document.id)
            }
        }
        .task(id: model.launchAttempt) {
            await model.restoreCurrentLaunchAttempt(windowFrame: currentWindowFrame)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 480, minHeight: 320)
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
}
