import XCTest
@testable import Scratchpad

final class JSONStoreTests: XCTestCase {
    struct Doc: Codable, Equatable { var schemaVersion = 1; var body: String }

    func makeDirs() throws -> (dir: URL, quarantine: URL) {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)")
        let q = d.appendingPathComponent("quarantine")
        try FileManager.default.createDirectory(at: q, withIntermediateDirectories: true)
        return (d, q)
    }

    func testRoundTrip() throws {
        let (dir, q) = try makeDirs()
        let store = JSONStore(quarantineDirectory: q)
        let url = dir.appendingPathComponent("s.json")
        try store.save(Doc(body: "hi"), to: url)
        XCTAssertEqual(try store.load(Doc.self, from: url), Doc(body: "hi"))
    }

    func testMissingFileReturnsNil() throws {
        let (dir, q) = try makeDirs()
        let store = JSONStore(quarantineDirectory: q)
        XCTAssertNil(try store.load(Doc.self, from: dir.appendingPathComponent("nope.json")))
    }

    func testCorruptFileIsQuarantinedNotDeleted() throws {
        let (dir, q) = try makeDirs()
        let store = JSONStore(quarantineDirectory: q)
        let url = dir.appendingPathComponent("bad.json")
        try Data("{not json!".utf8).write(to: url)
        XCTAssertNil(try store.load(Doc.self, from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: q.path)
        XCTAssertEqual(quarantined.count, 1)
    }
}
