import Foundation

enum EditorCommandRouter {
    static func outcome(
        for command: EditorCommand,
        text: String,
        selection: NSRange,
        context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        let table = LineTable(text)
        let safeSelection = table.clamped(selection)
        switch command {
        case .duplicateLine: return duplicate(table, safeSelection, context)
        case .deleteLine: return delete(table, safeSelection)
        case .moveLinesUp: return move(table, safeSelection, context, direction: -1)
        case .moveLinesDown: return move(table, safeSelection, context, direction: 1)
        case .selectLine:
            let indices = table.lineIndices(intersecting: safeSelection)
            return .selection(covering(indices, in: table))
        case .joinLines: return join(table, safeSelection)
        case .indent: return indent(table, safeSelection, context)
        case .outdent: return outdent(table, safeSelection, context)
        case .insertLineAfter: return insertLine(table, safeSelection, context, before: false)
        case .insertLineBefore: return insertLine(table, safeSelection, context, before: true)
        }
    }

    private static func duplicate(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        if selection.length > 0 {
            let selected = table.substring(selection)
            return edit(
                [TextMutation(
                    range: NSRange(location: NSMaxRange(selection), length: 0),
                    replacementText: selected
                )],
                NSRange(location: selection.location + selection.length, length: selection.length)
            )
        }
        let index = table.lineIndex(containing: selection.location)
        let line = table.lines[index]
        let column = selection.location - line.content.location
        if line.terminator.length > 0 {
            let original = table.substring(line.full)
            return edit(
                [TextMutation(
                    range: NSRange(location: NSMaxRange(line.full), length: 0),
                    replacementText: original
                )],
                NSRange(location: selection.location + line.full.length, length: 0)
            )
        }
        let content = table.substring(line.content)
        let insertionLocation = NSMaxRange(line.content)
        let replacement = context.newline + content
        let location = insertionLocation
            + context.newline.utf16.count + min(column, line.content.length)
        return edit(
            [TextMutation(
                range: NSRange(location: insertionLocation, length: 0),
                replacementText: replacement
            )],
            NSRange(location: location, length: 0)
        )
    }

    private static func delete(
        _ table: LineTable,
        _ selection: NSRange
    ) -> EditorCommandOutcome? {
        let indices = table.lineIndices(intersecting: selection)
        var range = covering(indices, in: table)
        let last = table.lines[indices.upperBound]
        if indices.upperBound == table.lines.count - 1,
           last.terminator.length == 0,
           indices.lowerBound > 0 {
            let previousTerminator = table.lines[indices.lowerBound - 1].terminator
            range = NSRange(
                location: previousTerminator.location,
                length: NSMaxRange(range) - previousTerminator.location
            )
        }
        if range.length == 0 { return nil }
        return edit(
            [TextMutation(range: range, replacementText: "")],
            NSRange(location: range.location, length: 0)
        )
    }

    private static func move(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext,
        direction: Int
    ) -> EditorCommandOutcome? {
        let selected = table.lineIndices(intersecting: selection)
        let neighbor = direction < 0 ? selected.lowerBound - 1 : selected.upperBound + 1
        guard table.lines.indices.contains(neighbor) else { return nil }
        let affected = direction < 0
            ? neighbor ... selected.upperBound
            : selected.lowerBound ... neighbor
        var contents = affected.map { table.substring(table.lines[$0].content) }
        if direction < 0 {
            let first = contents.removeFirst()
            contents.append(first)
        } else {
            let last = contents.removeLast()
            contents.insert(last, at: 0)
        }
        let affectedRange = covering(affected, in: table)
        let hasTrailingTerminator = table.lines[affected.upperBound].terminator.length > 0
        let replacement = contents.joined(separator: context.newline)
            + (hasTrailingTerminator ? context.newline : "")
        let neighborWidth = table.lines[neighbor].content.length + context.newline.utf16.count
        let shiftedLocation = selection.location + (direction < 0 ? -neighborWidth : neighborWidth)
        let resultingLength = table.source.utf16.count
            - affectedRange.length + replacement.utf16.count
        let safeLocation = min(max(0, shiftedLocation), resultingLength)
        let safeLength = min(selection.length, resultingLength - safeLocation)
        return edit(
            [TextMutation(range: affectedRange, replacementText: replacement)],
            NSRange(location: safeLocation, length: safeLength)
        )
    }

    private static func join(
        _ table: LineTable,
        _ selection: NSRange
    ) -> EditorCommandOutcome? {
        var indices = table.lineIndices(intersecting: selection)
        if indices.lowerBound == indices.upperBound {
            guard indices.upperBound + 1 < table.lines.count else { return nil }
            indices = indices.lowerBound ... indices.upperBound + 1
        }
        var mutations: [TextMutation] = []
        for index in indices.lowerBound ..< indices.upperBound {
            let current = table.lines[index]
            let next = table.lines[index + 1]
            let indentation = table.leadingIndentation(at: index + 1).utf16.count
            mutations.append(TextMutation(
                range: NSRange(
                    location: current.content.location + current.content.length,
                    length: current.terminator.length + indentation
                ),
                replacementText: " "
            ))
            _ = next
        }
        let caret = table.lines[indices.lowerBound].content.location
            + table.lines[indices.lowerBound].content.length + 1
        return edit(mutations, NSRange(location: caret, length: 0))
    }

    private static func indent(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        guard !context.indentationUnit.isEmpty else { return nil }
        let indices = table.lineIndices(intersecting: selection)
        let width = context.indentationUnit.utf16.count
        let mutations = indices.map {
            TextMutation(
                range: NSRange(location: table.lines[$0].content.location, length: 0),
                replacementText: context.indentationUnit
            )
        }
        let start = mapInsertionPosition(selection.location, mutations: mutations, width: width)
        let end = mapInsertionPosition(NSMaxRange(selection), mutations: mutations, width: width)
        return edit(mutations, NSRange(location: start, length: max(0, end - start)))
    }

    private static func outdent(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext
    ) -> EditorCommandOutcome? {
        let text = table.source as NSString
        let indices = table.lineIndices(intersecting: selection)
        var mutations: [TextMutation] = []
        for index in indices {
            let start = table.lines[index].content.location
            guard table.lines[index].content.length > 0 else { continue }
            var length = 0
            if text.character(at: start) == 9 {
                length = 1
            } else {
                while length < min(context.tabWidth, table.lines[index].content.length),
                      text.character(at: start + length) == 32 {
                    length += 1
                }
            }
            if length > 0 {
                mutations.append(TextMutation(
                    range: NSRange(location: start, length: length),
                    replacementText: ""
                ))
            }
        }
        guard !mutations.isEmpty else { return nil }
        let start = mapRemovalPosition(selection.location, mutations: mutations)
        let end = mapRemovalPosition(NSMaxRange(selection), mutations: mutations)
        return edit(mutations, NSRange(location: start, length: max(0, end - start)))
    }

    private static func insertLine(
        _ table: LineTable,
        _ selection: NSRange,
        _ context: EditorCommandContext,
        before: Bool
    ) -> EditorCommandOutcome? {
        let index = table.lineIndex(containing: selection.location)
        let line = table.lines[index]
        let indentation = context.keepsIndentation ? table.leadingIndentation(at: index) : ""
        if before {
            return edit(
                [TextMutation(range: NSRange(location: line.full.location, length: 0), replacementText: indentation + context.newline)],
                NSRange(location: line.full.location + indentation.utf16.count, length: 0)
            )
        }
        if line.terminator.length > 0 {
            return edit(
                [TextMutation(range: NSRange(location: NSMaxRange(line.full), length: 0), replacementText: indentation + context.newline)],
                NSRange(location: NSMaxRange(line.full) + indentation.utf16.count, length: 0)
            )
        }
        return edit(
            [TextMutation(range: NSRange(location: NSMaxRange(line.content), length: 0), replacementText: context.newline + indentation)],
            NSRange(location: NSMaxRange(line.content) + context.newline.utf16.count + indentation.utf16.count, length: 0)
        )
    }

    private static func covering(
        _ indices: ClosedRange<Int>,
        in table: LineTable
    ) -> NSRange {
        let start = table.lines[indices.lowerBound].full.location
        let end = NSMaxRange(table.lines[indices.upperBound].full)
        return NSRange(location: start, length: end - start)
    }

    private static func edit(
        _ mutations: [TextMutation],
        _ selection: NSRange
    ) -> EditorCommandOutcome {
        .edit(TextEdit(mutations: mutations, resultingSelection: selection))
    }

    private static func mapInsertionPosition(
        _ position: Int,
        mutations: [TextMutation],
        width: Int
    ) -> Int {
        position + mutations.filter { $0.range.location <= position }.count * width
    }

    private static func mapRemovalPosition(
        _ position: Int,
        mutations: [TextMutation]
    ) -> Int {
        position - mutations.reduce(0) { total, mutation in
            total + min(max(0, position - mutation.range.location), mutation.range.length)
        }
    }
}
