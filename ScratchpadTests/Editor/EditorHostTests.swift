import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class EditorHostTests: XCTestCase {
    private let viewport = NSRect(x: 0, y: 0, width: 480, height: 320)

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

    func testHostRestoresSelectionAndScrollAfterDocumentViewAttachment() throws {
        let text = (1...300).map { "line \($0) recovery scroll content" }.joined(separator: "\n")
        let selection = TextSelection(location: 3_725, length: 24)
        let document = DocumentSession(
            text: text,
            hasUnsavedChanges: true,
            generation: 1,
            selection: selection,
            scrollOffsetY: 1_796
        )
        var metadataCallbackCount = 0
        let coordinator = EditorCoordinator(
            document: document,
            onEdit: { _ in },
            onStateChange: { _ in metadataCallbackCount += 1 }
        )

        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: coordinator
        )
        let window = attachToWindow(scrollView)
        let textView = try textView(in: scrollView)

        XCTAssertNotNil(window.contentView)
        XCTAssertEqual(textView.selectedRange(), selection.nsRange)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 1_796, accuracy: 1)
        XCTAssertEqual(metadataCallbackCount, 0)
    }

    func testHostClampsRestoredScrollToDocumentBounds() throws {
        let text = (1...80).map { "line \($0)" }.joined(separator: "\n")
        let document = DocumentSession(text: text, scrollOffsetY: 100_000)
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })

        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: coordinator
        )
        _ = attachToWindow(scrollView)
        let textView = try textView(in: scrollView)
        let maximumOffset = max(
            0,
            textView.bounds.height - scrollView.contentView.bounds.height
        )

        XCTAssertGreaterThan(maximumOffset, 0)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.y,
            maximumOffset,
            accuracy: 1
        )

        let zeroDocument = DocumentSession(text: text, scrollOffsetY: 0)
        let zeroScrollView = EditorHost.makeScrollView(
            document: zeroDocument,
            coordinator: EditorCoordinator(document: zeroDocument, onEdit: { _ in })
        )
        _ = attachToWindow(zeroScrollView)
        XCTAssertEqual(zeroScrollView.contentView.bounds.origin.y, 0, accuracy: 0.5)
    }

    private func attachToWindow(_ scrollView: NSScrollView) -> NSWindow {
        let window = NSWindow(
            contentRect: viewport,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.contentView?.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
        return window
    }
}

private enum EditorHostTestError: Error {
    case missingTextView
}
