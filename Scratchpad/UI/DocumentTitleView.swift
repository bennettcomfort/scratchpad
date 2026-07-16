import AppKit
import SwiftUI

struct DocumentTitlePresentation: Equatable {
    let title: String
    let accessibilityValue: String

    init(displayName: String, hasUnsavedChanges: Bool) {
        title = hasUnsavedChanges ? "\(displayName) — Edited" : displayName
        accessibilityValue = hasUnsavedChanges ? "Edited" : "Saved"
    }
}

struct DocumentTitleView: View {
    let presentation: DocumentTitlePresentation
    let theme: ThemeDefinition

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .symbolRenderingMode(.monochrome)
            Text(presentation.title)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(nsColor: theme.editorForeground))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: theme.titleRegion))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Document title")
        .accessibilityValue(presentation.accessibilityValue)
    }
}
