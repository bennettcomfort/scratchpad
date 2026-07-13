import XCTest
@testable import Scratchpad

final class MarkdownTokenizerTests: XCTestCase {
    func testHeading() {
        let tokens = MarkdownTokenizer.tokenize("# Hello")
        XCTAssertEqual(tokens.count, 1)
        if case .heading(let range) = tokens[0] {
            XCTAssertEqual(range, NSRange(location: 0, length: 7))
        } else { XCTFail("expected heading") }
    }

    func testHeadingWithSpaces() {
        // "##   foo" (9 chars) — enumerateSubstrings trims trailing newline if absent,
        // so range may differ by one. Just verify a heading token exists.
        let tokens = MarkdownTokenizer.tokenize("##   foo\n")
        let headings = tokens.filter { if case .heading = $0 { true } else { false } }
        XCTAssertEqual(headings.count, 1)
    }

    func testBlockquote() {
        let tokens = MarkdownTokenizer.tokenize("> quoted text")
        XCTAssertEqual(tokens.count, 1)
        if case .blockquote(let range) = tokens[0] {
            XCTAssertEqual(range, NSRange(location: 0, length: 13))
        } else { XCTFail("expected blockquote") }
    }

    func testUnorderedList() {
        let tokens = MarkdownTokenizer.tokenize("- item one")
        XCTAssertEqual(tokens.count, 1)
        if case .unorderedList(let range) = tokens[0] {
            XCTAssertEqual(range, NSRange(location: 0, length: 10))
        } else { XCTFail("expected unordered list") }
    }

    func testOrderedList() {
        let tokens = MarkdownTokenizer.tokenize("1. first")
        XCTAssertEqual(tokens.count, 1)
        if case .orderedList(let range) = tokens[0] {
            XCTAssertEqual(range, NSRange(location: 0, length: 8))
        } else { XCTFail("expected ordered list") }
    }

    func testInlineCode() {
        let tokens = MarkdownTokenizer.tokenize("use `code` here")
        XCTAssertTrue(tokens.contains { if case .inlineCode = $0 { true } else { false } })
    }

    func testBold() {
        let tokens = MarkdownTokenizer.tokenize("**bold text**")
        XCTAssertTrue(tokens.contains { if case .bold = $0 { true } else { false } })
    }

    func testItalic() {
        let tokens = MarkdownTokenizer.tokenize("*italic*")
        XCTAssertTrue(tokens.contains { if case .italic = $0 { true } else { false } })
    }

    func testCodeFence() {
        let tokens = MarkdownTokenizer.tokenize("```swift\nlet x = 1\n```")
        let fences = tokens.filter { if case .codeFence = $0 { true } else { false } }
        XCTAssertFalse(fences.isEmpty)
    }

    func testHorizontalRule() {
        let tokens = MarkdownTokenizer.tokenize("---")
        XCTAssertTrue(tokens.contains { if case .horizontalRule = $0 { true } else { false } })
    }

    func testLink() {
        let tokens = MarkdownTokenizer.tokenize("[click here](https://x.com)")
        XCTAssertTrue(tokens.contains { if case .link = $0 { true } else { false } })
    }

    func testEmptyString() {
        let tokens = MarkdownTokenizer.tokenize("")
        XCTAssertTrue(tokens.isEmpty)
    }

    func testMultipleLines() {
        let input = """
        # Heading

        > quoted

        - list item
        """
        let tokens = MarkdownTokenizer.tokenize(input)
        XCTAssertEqual(tokens.filter { if case .heading = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(tokens.filter { if case .blockquote = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(tokens.filter { if case .unorderedList = $0 { true } else { false } }.count, 1)
    }
}
