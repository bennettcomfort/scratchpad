import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class AppCommandsTests: XCTestCase {
    private func assembly() throws -> (DocumentSession, NSWindow, ScratchTextView) {
        let document = DocumentSession(text: "one")
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw AppCommandsTestError.missingTextView
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return (document, window, textView)
    }

    func testResponderActionReachesFocusedScratchTextViewExactlyOnce() throws {
        let _ = AppCommands()
        let (document, window, textView) = try assembly()
        defer { window.close() }
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        XCTAssertTrue(window.makeFirstResponder(textView))

        let responder = try XCTUnwrap(window.firstResponder)
        let handled = responder.tryToPerform(
            #selector(ScratchTextView.scratchpadDuplicateLine(_:)),
            with: nil
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(document.storage.string, "one\none")
        XCTAssertEqual(document.generation, 1)
    }

    func testResponderActionDoesNotEditWithNonEditorFirstResponder() throws {
        let _ = AppCommands()
        let (document, window, _) = try assembly()
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))

        let responder = try XCTUnwrap(window.firstResponder)
        let handled = responder.tryToPerform(
            #selector(ScratchTextView.scratchpadDuplicateLine(_:)),
            with: nil
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(document.storage.string, "one")
        XCTAssertEqual(document.generation, 0)
    }
}

private enum AppCommandsTestError: Error { case missingTextView }
