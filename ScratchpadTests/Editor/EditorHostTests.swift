import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class EditorHostTests: XCTestCase {
    private func textView(in scrollView: NSScrollView) throws -> ScratchTextView {
        guard let textView = scrollView.documentView as? ScratchTextView else {
            throw EditorHostTestError.missingTextView
        }
        return textView
    }

    func testHostUsesTextKit2AndSessionStorage() throws {
        let document = DocumentSession(text: "alpha")
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: coordinator
        )
        let textView = try textView(in: scrollView)

        XCTAssertNotNil(textView.textLayoutManager)
        XCTAssertTrue(textView.textStorage === document.storage)
        XCTAssertEqual(textView.string, "alpha")
    }

    func testSeparateHostsCannotShareOrCrossEditStorage() throws {
        let first = DocumentSession(text: "first")
        let second = DocumentSession(text: "second")
        let firstView = try textView(in: EditorHost.makeScrollView(
            document: first,
            coordinator: EditorCoordinator(document: first, onEdit: { _ in })
        ))
        let secondView = try textView(in: EditorHost.makeScrollView(
            document: second,
            coordinator: EditorCoordinator(document: second, onEdit: { _ in })
        ))

        firstView.insertText("!", replacementRange: NSRange(location: 5, length: 0))

        XCTAssertTrue(firstView.textStorage === first.storage)
        XCTAssertTrue(secondView.textStorage === second.storage)
        XCTAssertEqual(first.storage.string, "first!")
        XCTAssertEqual(second.storage.string, "second")
    }
}

private enum EditorHostTestError: Error {
    case missingTextView
}
