import AppKit
import SwiftUI

struct ErrorBannerView: View {
    let banner: ErrorBanner
    let theme: ThemeDefinition
    let onAction: (BannerAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .symbolRenderingMode(.monochrome)
            Text(banner.message)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(banner.actions.enumerated()), id: \.offset) { _, action in
                Button(label(for: action)) {
                    onAction(action)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(nsColor: theme.editorForeground))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: theme.banner))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error")
    }

    private func label(for action: BannerAction) -> String {
        switch action {
        case .dismiss:
            "Dismiss"
        case .retry:
            "Retry"
        case .saveAs:
            "Save As…"
        case .reselectFile:
            "Select File…"
        case .openRecoveryFolder:
            "Open Recovery Folder"
        }
    }
}
