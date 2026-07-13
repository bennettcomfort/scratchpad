import SwiftUI

struct StatusBarView: View {
    let buffer: OpenBuffer
    let theme: EditorTheme

    private var text: String { buffer.storage.string }
    private var charCount: Int { text.count }
    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
    private var lineCount: Int {
        text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var body: some View {
        HStack {
            Text("\(charCount) Characters  |  \(wordCount) Words  |  \(lineCount) Lines")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondary)
            Spacer()
            Text("Unicode (UTF-8)")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondary)
        }
        .padding(.horizontal, 22)
        .frame(height: 28)
        .background(theme.background)
    }
}
