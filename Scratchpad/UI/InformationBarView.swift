import AppKit
import SwiftUI

struct InformationBarPresentation: Equatable {
    static let tokenHelpText = "Estimated token count. Exact counts vary by model."

    let metricsText: String
    let encodingText = "Unicode (UTF-8)"

    init(metrics: DocumentMetrics) {
        metricsText = "\(metrics.characters) characters · \(metrics.words) words · \(metrics.lines) lines · ~\(metrics.estimatedTokens) tokens"
    }
}

struct InformationBarView: View {
    let presentation: InformationBarPresentation
    let theme: ThemeDefinition

    var body: some View {
        HStack(spacing: 12) {
            Text(presentation.metricsText)
                .help(InformationBarPresentation.tokenHelpText)
            Spacer(minLength: 12)
            Text(presentation.encodingText)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(nsColor: theme.mutedText))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: theme.informationBar))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Document information")
        .accessibilityValue("\(presentation.metricsText), \(presentation.encodingText)")
    }
}
