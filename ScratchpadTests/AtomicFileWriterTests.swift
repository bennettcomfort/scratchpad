import XCTest
@testable import Scratchpad

final class AtomicFileWriterTests: XCTestCase {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testWritesNewFile() throws {
        let url = try tempDir().appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("hello".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
    }

    func testReplacesExistingFileCompletely() throws {
        let url = try tempDir().appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("first-longer-content".utf8), to: url)
        try AtomicFileWriter.write(Data("second".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
    }

    func testLeavesNoTempFilesBehind() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("a.json")
        try AtomicFileWriter.write(Data("x".utf8), to: url)
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents, ["a.json"])
    }
}
