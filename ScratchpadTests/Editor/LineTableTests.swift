import Foundation
import XCTest
@testable import Scratchpad

final class LineTableTests: XCTestCase {
    func testParsesLFAndTrailingEmptyLine() {
        let table = LineTable("one\ntwo\n")
        XCTAssertEqual(table.lines.count, 3)
        XCTAssertEqual(table.lines[0].content, NSRange(location: 0, length: 3))
        XCTAssertEqual(table.lines[0].terminator, NSRange(location: 3, length: 1))
        XCTAssertEqual(table.lines[2].full, NSRange(location: 8, length: 0))
    }

    func testTreatsCRLFAsOneTerminator() {
        let table = LineTable("one\r\ntwo")
        XCTAssertEqual(table.lines.count, 2)
        XCTAssertEqual(table.lines[0].terminator, NSRange(location: 3, length: 2))
        XCTAssertEqual(table.lines[1].content, NSRange(location: 5, length: 3))
    }

    func testSelectionEndingAtNextLineStartDoesNotSelectNextLine() {
        let table = LineTable("one\ntwo\nthree")
        XCTAssertEqual(
            table.lineIndices(intersecting: NSRange(location: 0, length: 4)),
            0 ... 0
        )
        XCTAssertEqual(
            table.lineIndices(intersecting: NSRange(location: 1, length: 5)),
            0 ... 1
        )
    }
}
