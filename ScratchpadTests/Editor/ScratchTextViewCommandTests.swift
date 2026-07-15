import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class ScratchTextViewCommandTests: XCTestCase {
    private func assembly(
        text: String,
        saveState: DocumentSaveState = .untitled,
        onEdit: @escaping @MainActor (DocumentSession) -> Void = { _ in }
    ) throws -> (DocumentSession, NSWindow, ScratchTextView) {
        let document = DocumentSession(text: text, saveState: saveState)
        let coordinator = EditorCoordinator(document: document, onEdit: onEdit)
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw ScratchCommandTestError.missingTextView
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        return (document, window, textView)
    }

    func testDuplicateActionFiresOnceAndUndoesAsOneOperation() throws {
        var editCount = 0
        let (document, _, textView) = try assembly(text: "one") { _ in editCount += 1 }
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        textView.scratchpadDuplicateLine(nil)

        XCTAssertEqual(document.storage.string, "one\none")
        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(editCount, 1)
        guard let undoManager = textView.undoManager else {
            XCTFail("window-backed editor requires undo manager")
            return
        }
        undoManager.undo()
        XCTAssertEqual(document.storage.string, "one")
    }

    func testMultiLineIndentPreservesAttributesAndUndoesOnce() throws {
        let attribute = NSAttributedString.Key("ScratchpadCommandTest")
        let (document, _, textView) = try assembly(text: "a\nb")
        document.storage.addAttribute(
            attribute,
            value: true,
            range: NSRange(location: 0, length: document.storage.length)
        )
        textView.setSelectedRange(NSRange(location: 0, length: 3))

        textView.scratchpadIndent(nil)

        XCTAssertEqual(document.storage.string, "\ta\n\tb")
        XCTAssertNotNil(document.storage.attribute(attribute, at: 1, effectiveRange: nil))
        XCTAssertNotNil(document.storage.attribute(attribute, at: 4, effectiveRange: nil))
        guard let undoManager = textView.undoManager else {
            XCTFail("window-backed editor requires undo manager")
            return
        }
        undoManager.undo()
        XCTAssertEqual(document.storage.string, "a\nb")
        XCTAssertFalse(undoManager.canUndo)
    }

    func testSelectLineChangesSelectionWithoutDirtyingDocument() throws {
        let (document, _, textView) = try assembly(text: "one\ntwo", saveState: .clean)
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.scratchpadSelectLine(nil)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 3))
        XCTAssertEqual(document.storage.string, "one\ntwo")
        XCTAssertEqual(document.generation, 0)
        XCTAssertEqual(document.saveState, .clean)
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)
    }

    func testEveryTextChangingCommandUndoesInOneOperation() throws {
        let cases: [(String, NSRange, @MainActor (ScratchTextView) -> Void)] = [
            ("one", NSRange(location: 1, length: 0), { $0.scratchpadDuplicateLine(nil) }),
            ("one\ntwo", NSRange(location: 1, length: 0), { $0.scratchpadDeleteLine(nil) }),
            ("one\ntwo", NSRange(location: 5, length: 0), { $0.scratchpadMoveLinesUp(nil) }),
            ("one\ntwo", NSRange(location: 1, length: 0), { $0.scratchpadMoveLinesDown(nil) }),
            ("one\ntwo", NSRange(location: 1, length: 0), { $0.scratchpadJoinLines(nil) }),
            ("one\ntwo", NSRange(location: 0, length: 7), { $0.scratchpadIndent(nil) }),
            ("\tone", NSRange(location: 1, length: 0), { $0.scratchpadOutdent(nil) }),
            ("  one", NSRange(location: 3, length: 0), { $0.scratchpadInsertLineAfter(nil) }),
            ("  one", NSRange(location: 3, length: 0), { $0.scratchpadInsertLineBefore(nil) })
        ]

        for (text, selection, invoke) in cases {
            let (document, _, textView) = try assembly(text: text)
            textView.setSelectedRange(selection)
            invoke(textView)
            XCTAssertNotEqual(document.storage.string, text)
            guard let undoManager = textView.undoManager else {
                XCTFail("window-backed editor requires undo manager")
                return
            }
            undoManager.undo()
            XCTAssertEqual(document.storage.string, text)
            XCTAssertFalse(undoManager.canUndo)
        }
    }
}

private enum ScratchCommandTestError: Error { case missingTextView }
