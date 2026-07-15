import XCTest
@testable import Scratchpad

@MainActor
final class ApplicationModelTests: XCTestCase {
    func testModelOwnsExactlyTheInjectedDocument() {
        let document = DocumentSession(text: "owned")
        let model = ApplicationModel(document: document)

        XCTAssertTrue(model.document === document)
        XCTAssertEqual(model.document.storage.string, "owned")
    }
}
