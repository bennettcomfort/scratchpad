import Foundation

enum DocumentSaveState: String, Codable, Equatable, Sendable {
    case untitled
    case edited
    case clean
    case conflicted
    case deleted
    case readOnly
}

enum LineEnding: String, Codable, Equatable, Sendable {
    case lf
    case crlf
}

enum WholeTextReplacementSource: Sendable {
    case initialUntitled
    case fileOpen
    case sessionRestore
    case confirmedDiskReload
}

struct TextSelection: Codable, Equatable, Sendable {
    var location: Int
    var length: Int

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    func clamped(toUTF16Length textLength: Int) -> Self {
        let safeTextLength = max(0, textLength)
        let safeLocation = min(max(0, location), safeTextLength)
        let remainingLength = safeTextLength - safeLocation
        let safeLength = min(max(0, length), remainingLength)
        return Self(location: safeLocation, length: safeLength)
    }
}
