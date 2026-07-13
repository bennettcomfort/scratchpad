import XCTest
@testable import Scratchpad

final class FuzzyMatcherTests: XCTestCase {
    func testExactMatchScoresBest() {
        let score = FuzzyMatcher.score(query: "hello", candidate: "hello")
        XCTAssertEqual(score, 100)
    }

    func testPrefixMatchScoresHigh() {
        let score = FuzzyMatcher.score(query: "hel", candidate: "hello")
        XCTAssertEqual(score, 80)
    }

    func testConsecutiveMatch() {
        let score = FuzzyMatcher.score(query: "ell", candidate: "hello")
        XCTAssertEqual(score, 60)
    }

    func testSubsequenceMatch() {
        let score = FuzzyMatcher.score(query: "ho", candidate: "hello")
        XCTAssertEqual(score, 40)
    }

    func testNoMatchReturnsNegative() {
        let score = FuzzyMatcher.score(query: "xyz", candidate: "hello")
        XCTAssertLessThan(score, 0)
    }

    func testCaseInsensitive() {
        let score = FuzzyMatcher.score(query: "HELLO", candidate: "hello")
        XCTAssertEqual(score, 100)
    }
}
