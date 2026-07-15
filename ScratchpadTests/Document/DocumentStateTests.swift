import Foundation
import XCTest
@testable import Scratchpad

final class DocumentStateTests: XCTestCase {
    func testSelectionClampsToUTF16Bounds() {
        let selection = TextSelection(location: 1, length: 20)
        XCTAssertEqual(
            selection.clamped(toUTF16Length: 2),
            TextSelection(location: 1, length: 1)
        )
        XCTAssertEqual(
            TextSelection(location: -4, length: -2).clamped(toUTF16Length: 2),
            TextSelection(location: 0, length: 0)
        )
    }

    func testPersistedDocumentValuesRoundTrip() throws {
        let reference = ExternalFileReference(
            bookmarkID: UUID(),
            pathHint: "/Users/example/prompt.md"
        )
        let encoded = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(ExternalFileReference.self, from: encoded)

        XCTAssertEqual(decoded, reference)
        XCTAssertEqual(DocumentSaveState.edited.rawValue, "edited")
        XCTAssertEqual(LineEnding.crlf.rawValue, "crlf")
    }
}
