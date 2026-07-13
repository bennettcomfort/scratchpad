import AppKit

@MainActor
enum HighlightApplier {
    private static let log = Log.logger("highlight")

    static func apply(_ tokens: [MarkdownToken], to storage: NSTextStorage,
                      font: NSFont, textColor: NSColor) {
        // Clear existing attributes (except font) for the whole range.
        let fullRange = NSRange(location: 0, length: storage.length)

        // Set base font + color
        storage.addAttribute(.font, value: font, range: fullRange)
        storage.addAttribute(.foregroundColor, value: textColor, range: fullRange)

        let headingFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 1.18,
                                                      weight: .semibold)
        let secondaryColor = NSColor.secondaryLabelColor

        for token in tokens {
            let range: NSRange
            switch token {
            case .heading(let r):       range = r
            case .blockquote(let r):    range = r
            case .unorderedList(let r): range = r
            case .orderedList(let r):   range = r
            case .inlineCode(let r):    range = r
            case .bold(let r):          range = r
            case .italic(let r):        range = r
            case .codeFence(let r):     range = r
            case .horizontalRule(let r): range = r
            case .link(let r):          range = r
            }

            guard range.length > 0, range.upperBound <= storage.length else { continue }

            switch token {
            case .heading:
                storage.addAttribute(.font, value: headingFont, range: range)
            case .blockquote:
                storage.addAttribute(.foregroundColor, value: secondaryColor, range: range)
            case .inlineCode:
                storage.addAttribute(.backgroundColor,
                    value: NSColor.systemGray.withAlphaComponent(0.2), range: range)
                storage.addAttribute(.font,
                    value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
                    range: range)
            case .bold:
                storage.addAttribute(.font,
                    value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold),
                    range: range)
            case .italic:
                let italicDesc = font.fontDescriptor.withSymbolicTraits(.italic)
                let italicFont = NSFont(descriptor: italicDesc, size: font.pointSize)
                    ?? font
                storage.addAttribute(.font, value: italicFont, range: range)
            case .codeFence:
                storage.addAttribute(.backgroundColor,
                    value: NSColor.systemGray.withAlphaComponent(0.15), range: range)
            case .link:
                storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                     range: range)
            case .horizontalRule:
                storage.addAttribute(.foregroundColor, value: secondaryColor, range: range)
            case .unorderedList, .orderedList:
                break // just paragraph style handled elsewhere
            }
        }
    }
}
