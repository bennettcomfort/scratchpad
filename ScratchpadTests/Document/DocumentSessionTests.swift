import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class DocumentSessionTests: XCTestCase {
    func testEachSessionOwnsDistinctTextStorage() {
        let first = DocumentSession(text: "first")
        let second = DocumentSession(text: "second")

        XCTAssertFalse(first.storage === second.storage)
        first.storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "changed")
        XCTAssertEqual(first.storage.string, "changed")
        XCTAssertEqual(second.storage.string, "second")
    }

    func testUserEditIncrementsGenerationOnceAndMarksEditableStatesEdited() {
        let untitled = DocumentSession(text: "draft")
        untitled.noteUserEdit()
        XCTAssertEqual(untitled.generation, 1)
        XCTAssertEqual(untitled.saveState, .edited)
        XCTAssertTrue(untitled.hasUnsavedChanges)

        let conflicted = DocumentSession(text: "draft", saveState: .conflicted)
        conflicted.noteUserEdit()
        XCTAssertEqual(conflicted.generation, 1)
        XCTAssertEqual(conflicted.saveState, .conflicted)
        XCTAssertTrue(conflicted.hasUnsavedChanges)
    }

    func testWholeReplacementIsSanctionedAndClampsSelection() {
        let document = DocumentSession(text: "long text", saveState: .edited)
        document.replaceEntireContents(
            "hi",
            source: .confirmedDiskReload,
            selection: TextSelection(location: 8, length: 4)
        )

        XCTAssertEqual(document.storage.string, "hi")
        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(document.saveState, .clean)
        XCTAssertEqual(document.selection, TextSelection(location: 2, length: 0))
        XCTAssertFalse(document.isPerformingWholeTextReplacement)
    }

    func testSnapshotCopiesTextAndMetadata() {
        let id = UUID()
        let document = DocumentSession(
            id: id,
            text: "snapshot",
            displayName: "Prompt",
            saveState: .edited,
            hasUnsavedChanges: true,
            generation: 7,
            lineEnding: .crlf,
            selection: TextSelection(location: 2, length: 3),
            scrollOffsetY: 44
        )

        let snapshot = document.snapshot()
        document.storage.append(NSAttributedString(string: " changed"))

        XCTAssertEqual(snapshot.documentID, id)
        XCTAssertEqual(snapshot.text, "snapshot")
        XCTAssertEqual(snapshot.generation, 7)
        XCTAssertTrue(snapshot.hasUnsavedChanges)
        XCTAssertEqual(snapshot.selection, TextSelection(location: 2, length: 3))
        XCTAssertEqual(snapshot.scrollOffsetY, 44)
        XCTAssertEqual(snapshot.lineEnding, .crlf)
    }
}
