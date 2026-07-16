import AppKit
import SwiftUI

@MainActor
struct ThemePreviewPresentation {
    let theme: ThemeDefinition
    let font: NSFont
    let selectionForeground: NSColor

    init(settings: EditorSettingsSnapshot, effectiveAppearance: NSAppearance) {
        let style = ResolvedEditorStyle(
            settings: settings,
            effectiveAppearance: effectiveAppearance
        )
        theme = style.theme
        font = style.font
        selectionForeground = style.selectionForeground
    }
}

struct ThemePreviewView: View {
    let settings: EditorSettingsSnapshot
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        let effectiveAppearance = NSAppearance(named: appearanceName) ?? NSApp.effectiveAppearance
        let presentation = ThemePreviewPresentation(
            settings: settings,
            effectiveAppearance: effectiveAppearance
        )

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Scratchpad ")
                Text("preview")
                    .foregroundStyle(Color(nsColor: presentation.selectionForeground))
                    .background(Color(nsColor: presentation.theme.selection))
                Spacer()
            }
            .font(Font(presentation.font))
            .foregroundStyle(Color(nsColor: presentation.theme.editorForeground))
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
            .background(Color(nsColor: presentation.theme.editorBackground))

            Rectangle()
                .fill(Color(nsColor: presentation.theme.separator))
                .frame(height: 1)

            HStack {
                Text("18 characters · 2 words · 1 line · ~5 tokens")
                Spacer()
                Text("Unicode (UTF-8)")
            }
            .font(.caption)
            .foregroundStyle(Color(nsColor: presentation.theme.mutedText))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color(nsColor: presentation.theme.informationBar))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: presentation.theme.separator))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme preview")
    }
}
