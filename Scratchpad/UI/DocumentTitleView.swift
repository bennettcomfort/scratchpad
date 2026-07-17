import AppKit
import SwiftUI

struct DocumentTitlePresentation: Equatable {
    let title: String
    let accessibilityValue: String

    init(displayName: String, hasUnsavedChanges: Bool) {
        title = hasUnsavedChanges ? "\(displayName) — Edited" : displayName
        accessibilityValue = hasUnsavedChanges ? "Edited" : "Saved"
    }

    @MainActor
    init(document: DocumentSession) {
        self.init(
            displayName: document.displayName,
            hasUnsavedChanges: document.hasUnsavedChanges
        )
    }
}

struct DocumentTitleLayout {
    let nativeControlSafeInset: CGFloat = 80
    let lineLimit = 1
    let truncationMode: Text.TruncationMode = .tail

    func titleFrame(containerWidth: CGFloat) -> CGRect {
        CGRect(
            x: nativeControlSafeInset,
            y: 0,
            width: max(0, containerWidth - nativeControlSafeInset * 2),
            height: 44
        )
    }
}

struct DocumentTitleView: View {
    let presentation: DocumentTitlePresentation
    let theme: ThemeDefinition
    let layout = DocumentTitleLayout()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .symbolRenderingMode(.monochrome)
            Text(presentation.title)
                .lineLimit(layout.lineLimit)
                .truncationMode(layout.truncationMode)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(nsColor: theme.editorForeground))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, layout.nativeControlSafeInset)
        .background(Color(nsColor: theme.titleRegion))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document-title")
        .accessibilityLabel(presentation.title)
        .accessibilityValue(presentation.accessibilityValue)
    }
}
