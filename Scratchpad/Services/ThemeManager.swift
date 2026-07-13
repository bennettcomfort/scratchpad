import SwiftUI
import Observation

@MainActor @Observable
final class ThemeManager {
    var current: EditorTheme {
        didSet { UserDefaults.standard.set(current.name, forKey: "activeTheme") }
    }

    static let all: [EditorTheme] = [
        .scratchDark, .scratchLight, .system, .highContrast
    ]

    init() {
        let saved = UserDefaults.standard.string(forKey: "activeTheme")
        self.current = Self.all.first { $0.name == saved } ?? .scratchDark
    }

    func apply(to textView: NSTextView, theme: EditorTheme) {
        textView.font = NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: theme.leftPadding, height: theme.topPadding)
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.text)
        textView.insertionPointColor = NSColor(theme.text)

        if let ts = textView.textStorage {
            let range = NSRange(location: 0, length: ts.length)
            ts.addAttribute(.font,
                value: NSFont.monospacedSystemFont(ofSize: theme.fontSize, weight: .regular),
                range: range)
            ts.addAttribute(.foregroundColor, value: NSColor(theme.text), range: range)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = theme.lineHeight
        textView.defaultParagraphStyle = paragraph
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
            range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
    }
}
