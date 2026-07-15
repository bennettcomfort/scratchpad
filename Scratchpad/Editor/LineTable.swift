import Foundation

struct LineRecord: Equatable, Sendable {
    let content: NSRange
    let terminator: NSRange

    var full: NSRange {
        NSRange(
            location: content.location,
            length: content.length + terminator.length
        )
    }
}

struct LineTable: Sendable {
    let source: String
    let lines: [LineRecord]
    private let utf16Length: Int

    init(_ source: String) {
        self.source = source
        let text = source as NSString
        self.utf16Length = text.length
        var records: [LineRecord] = []
        var lineStart = 0
        var cursor = 0

        while cursor < text.length {
            let unit = text.character(at: cursor)
            guard unit == 10 || unit == 13 else {
                cursor += 1
                continue
            }
            let terminatorLength = unit == 13
                && cursor + 1 < text.length
                && text.character(at: cursor + 1) == 10 ? 2 : 1
            records.append(LineRecord(
                content: NSRange(location: lineStart, length: cursor - lineStart),
                terminator: NSRange(location: cursor, length: terminatorLength)
            ))
            cursor += terminatorLength
            lineStart = cursor
        }

        records.append(LineRecord(
            content: NSRange(location: lineStart, length: text.length - lineStart),
            terminator: NSRange(location: text.length, length: 0)
        ))
        self.lines = records
    }

    func clamped(_ range: NSRange) -> NSRange {
        let location = min(max(0, range.location), utf16Length)
        let length = min(max(0, range.length), utf16Length - location)
        return NSRange(location: location, length: length)
    }

    func lineIndex(containing location: Int) -> Int {
        let safeLocation = min(max(0, location), utf16Length)
        for (index, line) in lines.enumerated() {
            if safeLocation < NSMaxRange(line.full)
                || line.full.length == 0 && safeLocation == line.full.location {
                return index
            }
        }
        return max(0, lines.count - 1)
    }

    func lineIndices(intersecting range: NSRange) -> ClosedRange<Int> {
        let selection = clamped(range)
        let first = lineIndex(containing: selection.location)
        let endProbe = selection.length == 0
            ? selection.location
            : NSMaxRange(selection) - 1
        return first ... lineIndex(containing: endProbe)
    }

    func substring(_ range: NSRange) -> String {
        (source as NSString).substring(with: range)
    }

    func leadingIndentation(at index: Int) -> String {
        let content = substring(lines[index].content) as NSString
        var length = 0
        while length < content.length {
            let unit = content.character(at: length)
            guard unit == 9 || unit == 32 else { break }
            length += 1
        }
        return content.substring(with: NSRange(location: 0, length: length))
    }
}
