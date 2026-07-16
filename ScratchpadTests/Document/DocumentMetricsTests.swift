import XCTest
@testable import Scratchpad

final class DocumentMetricsTests: XCTestCase {
    func testEmptyDocumentReportsZeroCharactersWordsTokensAndOneLine() {
        let metrics = DocumentMetricsCalculator.calculate(
            text: "",
            countsWhitespace: false
        )

        XCTAssertEqual(metrics.characters, 0)
        XCTAssertEqual(metrics.words, 0)
        XCTAssertEqual(metrics.lines, 1)
        XCTAssertEqual(metrics.estimatedTokens, 0)
    }

    func testCharactersUseExtendedGraphemeClusters() {
        let text = "e\u{301} 👩‍💻\nhello\tworld"

        let metrics = DocumentMetricsCalculator.calculate(
            text: text,
            countsWhitespace: true
        )

        XCTAssertEqual(metrics.characters, 15)
    }

    func testWhitespaceToggleChangesOnlyCharacterCount() {
        let text = "e\u{301} 👩‍💻\nhello\tworld"

        let excludingWhitespace = DocumentMetricsCalculator.calculate(
            text: text,
            countsWhitespace: false
        )
        let includingWhitespace = DocumentMetricsCalculator.calculate(
            text: text,
            countsWhitespace: true
        )

        XCTAssertEqual(excludingWhitespace.characters, 12)
        XCTAssertEqual(includingWhitespace.characters, 15)
        XCTAssertEqual(excludingWhitespace.words, includingWhitespace.words)
        XCTAssertEqual(excludingWhitespace.lines, includingWhitespace.lines)
        XCTAssertEqual(
            excludingWhitespace.estimatedTokens,
            includingWhitespace.estimatedTokens
        )
        XCTAssertEqual(excludingWhitespace.isEstimate, includingWhitespace.isEstimate)
    }

    func testWordsAreNonemptyUnicodeWhitespaceSeparatedRuns() {
        let text = "e\u{301} 👩‍💻\nhello\tworld"

        let metrics = DocumentMetricsCalculator.calculate(
            text: text,
            countsWhitespace: false
        )

        XCTAssertEqual(metrics.words, 4)
    }

    func testLinesEqualNewlineCountPlusOne() {
        XCTAssertEqual(calculate("").lines, 1)
        XCTAssertEqual(calculate("\n").lines, 2)
        XCTAssertEqual(calculate("first\nsecond\n").lines, 3)
    }

    func testTokenEstimateUsesCeilingUTF8BytesDividedByFour() {
        XCTAssertEqual(calculate("").estimatedTokens, 0)
        XCTAssertEqual(calculate("a").estimatedTokens, 1)
        XCTAssertEqual(calculate("abcd").estimatedTokens, 1)
        XCTAssertEqual(calculate("abcde").estimatedTokens, 2)
    }

    func testEstimateFlagIsAlwaysTrueAndPresentationRequiresTilde() {
        let empty = calculate("")
        let nonempty = calculate("a")

        XCTAssertTrue(empty.isEstimate)
        XCTAssertTrue(nonempty.isEstimate)
        XCTAssertEqual("~\(nonempty.estimatedTokens)", "~1")
    }

    private func calculate(_ text: String) -> DocumentMetrics {
        DocumentMetricsCalculator.calculate(text: text, countsWhitespace: false)
    }
}
