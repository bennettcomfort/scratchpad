import Foundation
import XCTest
@testable import Scratchpad

final class EditorCommandRouterTests: XCTestCase {
    private let lf = EditorCommandContext.defaults(lineEnding: .lf)

    private func result(
        _ command: EditorCommand,
        text: String,
        selection: NSRange,
        context: EditorCommandContext? = nil
    ) throws -> (String, NSRange) {
        guard let outcome = EditorCommandRouter.outcome(
            for: command,
            text: text,
            selection: selection,
            context: context ?? lf
        ) else { throw RouterTestError.noOutcome }
        let value: (String, NSRange)
        switch outcome {
        case .selection(let range):
            value = (text, range)
        case .edit(let edit):
            let transformed = NSMutableString(string: text)
            for mutation in edit.mutations.reversed() {
                transformed.replaceCharacters(in: mutation.range, with: mutation.replacementText)
            }
            value = (transformed as String, edit.resultingSelection)
        }
        XCTAssertGreaterThanOrEqual(value.1.location, 0)
        XCTAssertGreaterThanOrEqual(value.1.length, 0)
        XCTAssertLessThanOrEqual(NSMaxRange(value.1), value.0.utf16.count)
        return value
    }

    func testDuplicateLineAndSelection() throws {
        XCTAssertEqual(
            try result(.duplicateLine, text: "one\ntwo", selection: NSRange(location: 1, length: 0)).0,
            "one\none\ntwo"
        )
        XCTAssertEqual(
            try result(.duplicateLine, text: "abc", selection: NSRange(location: 1, length: 1)).0,
            "abbc"
        )
    }

    func testDeleteLineIncludingFinalLineSeparator() throws {
        XCTAssertEqual(
            try result(.deleteLine, text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0)).0,
            "one\nthree"
        )
        XCTAssertEqual(
            try result(.deleteLine, text: "one\ntwo", selection: NSRange(location: 5, length: 0)).0,
            "one"
        )
    }

    func testDeleteTrailingEmptyLineRemovesSeparator() throws {
        let value = try result(
            .deleteLine,
            text: "one\n",
            selection: NSRange(location: 4, length: 0)
        )
        XCTAssertEqual(value.0, "one")
        XCTAssertEqual(value.1, NSRange(location: 3, length: 0))
    }

    func testMoveLinesUp() throws {
        let value = try result(.moveLinesUp, text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(value.0, "two\none\nthree")
        XCTAssertEqual(value.1, NSRange(location: 1, length: 0))
    }

    func testMoveLinesDown() throws {
        let value = try result(.moveLinesDown, text: "one\ntwo\nthree", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(value.0, "one\nthree\ntwo")
        XCTAssertEqual(value.1, NSRange(location: 11, length: 0))
    }

    func testMoveLinesDownClampsNewlineInclusiveSelectionAtEnd() throws {
        let value = try result(
            .moveLinesDown,
            text: "one\ntwo\nthree",
            selection: NSRange(location: 0, length: 8)
        )
        XCTAssertEqual(value.0, "three\none\ntwo")
        XCTAssertEqual(value.1, NSRange(location: 6, length: 7))
    }

    func testSelectLineDoesNotChangeText() throws {
        let value = try result(.selectLine, text: "one\ntwo", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(value.0, "one\ntwo")
        XCTAssertEqual(value.1, NSRange(location: 4, length: 3))
    }

    func testJoinLinesRemovesNewlineAndLeadingIndentation() throws {
        let value = try result(.joinLines, text: "one\n  two", selection: NSRange(location: 1, length: 0))
        XCTAssertEqual(value.0, "one two")
        XCTAssertEqual(value.1, NSRange(location: 4, length: 0))
    }

    func testIndentUsesNarrowInsertions() throws {
        guard let outcome = EditorCommandRouter.outcome(
            for: .indent,
            text: "a\nb",
            selection: NSRange(location: 0, length: 3),
            context: lf
        ), case .edit(let edit) = outcome else { throw RouterTestError.noOutcome }
        XCTAssertEqual(edit.mutations.map(\.range), [
            NSRange(location: 0, length: 0),
            NSRange(location: 2, length: 0)
        ])
        XCTAssertEqual(try result(.indent, text: "a\nb", selection: NSRange(location: 0, length: 3)).0, "\ta\n\tb")
    }

    func testOutdentRemovesOneTabOrUpToTabWidthSpaces() throws {
        XCTAssertEqual(
            try result(.outdent, text: "\ta\n    b", selection: NSRange(location: 0, length: 8)).0,
            "a\nb"
        )
    }

    func testInsertLineAfterCarriesIndentation() throws {
        let value = try result(.insertLineAfter, text: "  one", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(value.0, "  one\n  ")
        XCTAssertEqual(value.1, NSRange(location: 8, length: 0))
    }

    func testInsertLineBeforeCarriesIndentation() throws {
        let value = try result(.insertLineBefore, text: "  one", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(value.0, "  \n  one")
        XCTAssertEqual(value.1, NSRange(location: 2, length: 0))
    }

    func testCRLFCommandsPreserveCRLF() throws {
        let crlf = EditorCommandContext.defaults(lineEnding: .crlf)
        XCTAssertEqual(
            try result(.insertLineAfter, text: "one", selection: NSRange(location: 1, length: 0), context: crlf).0,
            "one\r\n"
        )
    }
}

private enum RouterTestError: Error { case noOutcome }
