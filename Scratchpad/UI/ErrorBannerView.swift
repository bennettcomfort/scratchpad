import AppKit
import SwiftUI

struct ErrorBannerView: View {
    let banner: ErrorBanner
    let theme: ThemeDefinition
    let onAction: (BannerAction) -> Void
    @FocusState private var focusedActionIndex: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .symbolRenderingMode(.monochrome)
            Text(banner.message)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(banner.actions.enumerated()), id: \.offset) { index, action in
                Button(label(for: action)) {
                    onAction(action)
                }
                .focused($focusedActionIndex, equals: index)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(nsColor: theme.editorForeground))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: theme.banner))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("error-banner")
        .accessibilityLabel("Error")
        .accessibilityValue(banner.message)
        .onAppear {
            focusedActionIndex = banner.actions.indices.first
        }
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
