import Foundation

enum EditorCommand: Sendable {
    case duplicateLine
    case deleteLine
    case moveLinesUp
    case moveLinesDown
    case selectLine
    case joinLines
    case indent
    case outdent
    case insertLineAfter
    case insertLineBefore
}

struct EditorCommandContext: Equatable, Sendable {
    let lineEnding: LineEnding
    let indentationUnit: String
    let tabWidth: Int
    let keepsIndentation: Bool

    static func defaults(lineEnding: LineEnding) -> Self {
        Self(
            lineEnding: lineEnding,
            indentationUnit: "\t",
            tabWidth: 4,
            keepsIndentation: true
        )
    }

    var newline: String {
        lineEnding == .crlf ? "\r\n" : "\n"
    }
}

struct TextMutation: Equatable, Sendable {
    let range: NSRange
    let replacementText: String
}

struct TextEdit: Equatable, Sendable {
    let mutations: [TextMutation]
    let resultingSelection: NSRange
}

enum EditorCommandOutcome: Equatable, Sendable {
    case selection(NSRange)
    case edit(TextEdit)
}
