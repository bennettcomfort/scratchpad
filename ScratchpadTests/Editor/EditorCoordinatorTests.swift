import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class EditorCoordinatorTests: XCTestCase {
    private func assembly(
        text: String = "alpha",
        onStateChange: @escaping @MainActor (DocumentSession) -> Void = { _ in },
        onEdit: @escaping @MainActor (DocumentSession) -> Void
    ) throws -> (DocumentSession, EditorCoordinator, NSWindow, NSScrollView, ScratchTextView) {
        let document = DocumentSession(text: text)
        let coordinator = EditorCoordinator(
            document: document,
            onEdit: onEdit,
            onStateChange: onStateChange
        )
        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: coordinator
        )
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw EditorCoordinatorTestError.missingTextView
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        return (document, coordinator, window, scrollView, textView)
    }

    func testNativeEditNotifiesOnceAndParticipatesInUndo() throws {
        var editCount = 0
        let (document, _, _, _, textView) = try assembly { _ in editCount += 1 }

        textView.insertText("!", replacementRange: NSRange(location: 5, length: 0))

        XCTAssertEqual(document.storage.string, "alpha!")
        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(document.saveState, .edited)
        XCTAssertEqual(editCount, 1)
        guard let undoManager = textView.undoManager else {
            XCTFail("NSTextView must provide an undo manager")
            return
        }
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(document.storage.string, "alpha")
    }

    func testSelectionAndScrollAreCapturedAndClamped() throws {
        var editCount = 0
        var stateChangeCount = 0
        let (document, coordinator, _, scrollView, textView) = try assembly(
            onStateChange: { _ in stateChangeCount += 1 },
            onEdit: { _ in editCount += 1 }
        )
        let initialGeneration = document.generation
        textView.setSelectedRange(NSRange(location: 2, length: 2))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 42))
        coordinator.clipViewBoundsDidChange(
            Notification(name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        )

        XCTAssertEqual(document.selection, TextSelection(location: 2, length: 2))
        XCTAssertEqual(document.scrollOffsetY, 42)
        XCTAssertEqual(document.generation, initialGeneration)
        XCTAssertFalse(document.hasUnsavedChanges)
        XCTAssertEqual(editCount, 0)
        XCTAssertEqual(stateChangeCount, 2)
    }

    func testWholeReplacementDoesNotEmitUserEditCallback() throws {
        var editCount = 0
        let (document, _, _, _, _) = try assembly { _ in editCount += 1 }

        document.replaceEntireContents(
            "restored",
            source: .sessionRestore,
            selection: TextSelection(location: 3, length: 0)
        )

        XCTAssertEqual(document.generation, 1)
        XCTAssertEqual(document.selection, TextSelection(location: 3, length: 0))
        XCTAssertEqual(editCount, 0)
    }

}

private enum EditorCoordinatorTestError: Error {
    case missingTextView
}
