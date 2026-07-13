import Foundation

enum MarkdownToken: Equatable, Sendable {
    case heading(NSRange)
    case blockquote(NSRange)
    case unorderedList(NSRange)
    case orderedList(NSRange)
    case inlineCode(NSRange)
    case bold(NSRange)
    case italic(NSRange)
    case codeFence(NSRange)
    case horizontalRule(NSRange)
    case link(NSRange)
}

enum MarkdownTokenizer {
    static func tokenize(_ text: String) -> [MarkdownToken] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var tokens: [MarkdownToken] = []
        var inFence = false

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: .byLines) { line, lineRange, _, _ in
            guard let line = line else { return }

            // Code fences
            if line.hasPrefix("```") {
                inFence.toggle()
                tokens.append(.codeFence(lineRange))
                return
            }
            if inFence {
                tokens.append(.codeFence(lineRange))
                return
            }

            // Headings
            if let headingRange = headingRange(line, in: ns, lineRange: lineRange) {
                tokens.append(.heading(headingRange))
            }
            // Blockquote
            else if line.hasPrefix(">") {
                tokens.append(.blockquote(lineRange))
            }
            // Unordered list
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                tokens.append(.unorderedList(lineRange))
            }
            // Ordered list
            else if let first = line.first, first.isNumber,
                    line.contains(". ") {
                tokens.append(.orderedList(lineRange))
            }
            // Horizontal rule
            else if line == "---" || line == "***" || line == "___" {
                tokens.append(.horizontalRule(lineRange))
            }

            // Inline tokens (can appear on any line)
            inlineTokens(line, in: ns, lineRange: lineRange).forEach {
                tokens.append($0)
            }
        }
        return tokens
    }

    private static func headingRange(_ line: String, in ns: NSString, lineRange: NSRange) -> NSRange? {
        let trimmed = line.trimmingPrefix(while: { $0 == "#" })
        let hashCount = line.count - trimmed.count
        guard hashCount >= 1, hashCount <= 6, trimmed.first == " " else { return nil }
        return lineRange
    }

    private static func inlineTokens(_ line: String, in ns: NSString, lineRange: NSRange) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []

        // Links: [text](url)
        let linkPattern = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
        if let matches = linkPattern?.matches(in: line, range: NSRange(location: 0, length: ns.substring(with: lineRange).count)) {
            for m in matches {
                tokens.append(.link(NSRange(location: lineRange.location + m.range.location,
                                            length: m.range.length)))
            }
        }

        // Bold: **text**
        let boldPattern = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
        if let matches = boldPattern?.matches(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            for m in matches {
                tokens.append(.bold(NSRange(location: lineRange.location + m.range.location,
                                            length: m.range.length)))
            }
        }

        // Italic: *text* (but not **)
        let italicPattern = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
        if let matches = italicPattern?.matches(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            for m in matches {
                tokens.append(.italic(NSRange(location: lineRange.location + m.range.location,
                                              length: m.range.length)))
            }
        }

        // Inline code: `code`
        let codePattern = try? NSRegularExpression(pattern: "`([^`]+)`")
        if let matches = codePattern?.matches(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
            for m in matches {
                tokens.append(.inlineCode(NSRange(location: lineRange.location + m.range.location,
                                                 length: m.range.length)))
            }
        }

        return tokens
    }
}

extension MarkdownToken: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .heading(let r): return ".heading(\(r))"
        case .blockquote(let r): return ".blockquote(\(r))"
        case .unorderedList(let r): return ".unorderedList(\(r))"
        case .orderedList(let r): return ".orderedList(\(r))"
        case .inlineCode(let r): return ".inlineCode(\(r))"
        case .bold(let r): return ".bold(\(r))"
        case .italic(let r): return ".italic(\(r))"
        case .codeFence(let r): return ".codeFence(\(r))"
        case .horizontalRule(let r): return ".horizontalRule(\(r))"
        case .link(let r): return ".link(\(r))"
        }
    }
}
