import XCTest
@testable import Scratchpad

@MainActor
final class BufferStoreTests: XCTestCase {
    func testCreateScratchBuffer() {
        let store = BufferStore()
        let b = store.createScratchBuffer()
        XCTAssertEqual(b.saveState, .scratch)
        XCTAssertNil(b.fileURL)
        XCTAssertEqual(store.buffers.count, 1)
        XCTAssertEqual(store.activeBufferID, b.id)
        XCTAssertEqual(b.generation, 0)
    }

    func testNoteEditedIncrementsGenerationAndDirties() {
        let store = BufferStore()
        let b = store.createScratchBuffer()
        b.noteEdited()
        XCTAssertEqual(b.generation, 1)
        XCTAssertEqual(b.saveState, .scratch) // scratch stays scratch, not .dirty
        b.fileURL = URL(fileURLWithPath: "/tmp/x.md"); b.saveState = .clean
        b.noteEdited()
        XCTAssertEqual(b.saveState, .dirty)
    }

    func testReplaceEntireContentsDoesNotDirty() {
        let store = BufferStore()
        let b = store.createScratchBuffer()
        b.replaceEntireContents("hello\nworld")
        XCTAssertEqual(b.text, "hello\nworld")
        XCTAssertEqual(b.generation, 1)          // restore bumps generation…
        XCTAssertEqual(b.saveState, .scratch)    // …but never marks dirty by itself
        XCTAssertEqual(b.firstLinePreview, "hello")
    }
}
