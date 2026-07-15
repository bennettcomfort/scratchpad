import Foundation
import XCTest
@testable import Scratchpad

final class RecoveryContainmentTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(at relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testRuntimeDeclaresBaselineContainmentStage() {
        XCTAssertEqual(RecoveryStage.current, .baselineContainment)
    }

    func testProjectUsesExplicitRecoveryAllowlists() throws {
        let project = try contents(at: "project.yml")

        XCTAssertFalse(project.contains("sources: [Scratchpad]"))
        XCTAssertFalse(project.contains("sources: [ScratchpadTests]"))
        XCTAssertTrue(project.contains("- path: Scratchpad/RecoveryBaseline"))
        XCTAssertTrue(project.contains("- path: Scratchpad/Assets.xcassets"))
        XCTAssertTrue(project.contains("- ScratchpadTests/SmokeTests.swift"))
        XCTAssertTrue(project.contains("- ScratchpadTests/RecoveryContainmentTests.swift"))
    }

    func testProjectTreatsSwiftWarningsAsErrors() throws {
        let project = try contents(at: "project.yml")
        XCTAssertTrue(project.contains("SWIFT_TREAT_WARNINGS_AS_ERRORS: YES"))
    }

    func testProjectDeclaresNoRuntimePackages() throws {
        let project = try contents(at: "project.yml")
        XCTAssertFalse(project.contains("\npackages:"))
    }

    func testEntitlementsDeclareNoNetworkAccess() throws {
        let entitlements = try contents(at: "Scratchpad/App/Scratchpad.entitlements")
        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"))
        XCTAssertFalse(entitlements.contains("com.apple.security.network.server"))
    }

    func testCIUsesProjectDeploymentTargetWithoutOverride() throws {
        let workflow = try contents(at: ".github/workflows/ci.yml")
        XCTAssertFalse(workflow.contains("MACOSX_DEPLOYMENT_TARGET"))
        XCTAssertTrue(workflow.contains("xcodebuild -scheme Scratchpad -destination 'platform=macOS' build"))
        XCTAssertTrue(workflow.contains("xcodebuild -scheme Scratchpad -destination 'platform=macOS' test"))
    }
}
