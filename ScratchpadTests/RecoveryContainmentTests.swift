import Foundation
import XCTest
@testable import Scratchpad

final class RecoveryContainmentTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRuntimeDeclaresBaselineContainmentStage() {
        XCTAssertEqual(RecoveryStage.current, .baselineContainment)
    }

    func testProjectUsesExplicitRecoveryAllowlists() throws {
        let projectURL = repositoryRoot.appendingPathComponent("project.yml")
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        XCTAssertFalse(project.contains("sources: [Scratchpad]"))
        XCTAssertFalse(project.contains("sources: [ScratchpadTests]"))
        XCTAssertTrue(project.contains("- path: Scratchpad/RecoveryBaseline"))
        XCTAssertTrue(project.contains("- path: Scratchpad/Assets.xcassets"))
        XCTAssertTrue(project.contains("- ScratchpadTests/SmokeTests.swift"))
        XCTAssertTrue(project.contains("- ScratchpadTests/RecoveryContainmentTests.swift"))
    }
}
