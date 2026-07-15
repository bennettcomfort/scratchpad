import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class AppCommandsTests: XCTestCase {
    private func assembly() throws -> (DocumentSession, ScratchTextView) {
        let document = DocumentSession(text: "one")
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw AppCommandsTestError.missingTextView
        }
        return (document, textView)
    }

    func testResponderActionReachesFocusedScratchTextViewExactlyOnce() throws {
        let _ = AppCommands()
        let (document, textView) = try assembly()
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        let handled = textView.tryToPerform(
            #selector(ScratchTextView.scratchpadDuplicateLine(_:)),
            with: nil
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(document.storage.string, "one\none")
        XCTAssertEqual(document.generation, 1)
    }

    func testResponderActionDoesNotEditWithNonEditorFirstResponder() throws {
        let _ = AppCommands()
        let (document, _) = try assembly()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))

        let handled = field.tryToPerform(
            #selector(ScratchTextView.scratchpadDuplicateLine(_:)),
            with: nil
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(document.storage.string, "one")
        XCTAssertEqual(document.generation, 0)
    }
}

private enum AppCommandsTestError: Error { case missingTextView }
