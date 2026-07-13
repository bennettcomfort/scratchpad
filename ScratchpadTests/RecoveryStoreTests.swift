import XCTest
@testable import Scratchpad

final class RecoveryStoreTests: XCTestCase {
    func makeStore() throws -> RecoveryStore {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)")
        let q = d.appendingPathComponent("q")
        try FileManager.default.createDirectory(at: q, withIntermediateDirectories: true)
        return RecoveryStore(directory: d, store: JSONStore(quarantineDirectory: q))
    }

    func testWriteLoadDeleteLifecycle() throws {
        let store = try makeStore()
        let id = UUID()
        let rb = RecoveryBuffer(bufferID: id, filePath: nil,
                                unsavedText: "draft", savedAt: Date())
        try store.write(rb)
        XCTAssertEqual(try store.loadAll().map(\.bufferID), [id])
        XCTAssertEqual(try store.loadAll().first?.unsavedText, "draft")
        try store.delete(bufferID: id)
        XCTAssertTrue(try store.loadAll().isEmpty)
    }

    func testOverwriteKeepsOneFilePerBuffer() throws {
        let store = try makeStore()
        let id = UUID()
        try store.write(RecoveryBuffer(bufferID: id, filePath: nil, unsavedText: "v1", savedAt: Date()))
        try store.write(RecoveryBuffer(bufferID: id, filePath: nil, unsavedText: "v2", savedAt: Date()))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.unsavedText, "v2")
    }
}
