import XCTest
@testable import Scratchpad

final class ApplicationSupportPathsTests: XCTestCase {
    func testDirectoryLayoutAndCreation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-test-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(root: root)
        XCTAssertEqual(paths.session.lastPathComponent, "session")
        XCTAssertEqual(paths.recovery.lastPathComponent, "recovery")
        XCTAssertEqual(paths.quarantine.lastPathComponent, "quarantine")
        try paths.ensureDirectoriesExist()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.recovery.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }
}
