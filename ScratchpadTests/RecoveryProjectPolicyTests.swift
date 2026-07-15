import Foundation
import XCTest

final class RecoveryProjectPolicyTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testProjectUsesExplicitReplacementSources() throws {
        let project = try contents(at: "project.yml")
        XCTAssertFalse(project.contains("sources: [Scratchpad]"))
        XCTAssertFalse(project.contains("Scratchpad/RecoveryBaseline"))
        XCTAssertTrue(project.contains("Scratchpad/App/ApplicationModel.swift"))
        XCTAssertTrue(project.contains("Scratchpad/Document/DocumentSession.swift"))
        XCTAssertTrue(project.contains("Scratchpad/Editor/EditorHost.swift"))
        XCTAssertTrue(
            try contents(at: "Scratchpad/App/ScratchpadApp.swift")
                .contains("TextEditingCommands()")
        )
    }

    func testProjectTreatsSwiftWarningsAsErrors() throws {
        XCTAssertTrue(
            try contents(at: "project.yml")
                .contains("SWIFT_TREAT_WARNINGS_AS_ERRORS: YES")
        )
    }

    func testProjectDeclaresNoRuntimePackages() throws {
        XCTAssertFalse(try contents(at: "project.yml").contains("\npackages:"))
    }

    func testEntitlementsDeclareNoNetworkAccess() throws {
        let entitlements = try contents(at: "Scratchpad/App/Scratchpad.entitlements")
        XCTAssertFalse(entitlements.contains("com.apple.security.network.client"))
        XCTAssertFalse(entitlements.contains("com.apple.security.network.server"))
    }

    func testCIUsesProjectDeploymentTargetWithoutOverride() throws {
        let workflow = try contents(at: ".github/workflows/ci.yml")
        XCTAssertFalse(workflow.contains("MACOSX_DEPLOYMENT_TARGET"))
    }
}
