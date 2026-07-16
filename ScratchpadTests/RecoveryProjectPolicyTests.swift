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

    func testProductionLaunchUsesLiveServicesAndConstructsEditorOnlyWhenReady() throws {
        let app = try contents(at: "Scratchpad/App/ScratchpadApp.swift")
        let window = try contents(at: "Scratchpad/App/MainWindowView.swift")

        XCTAssertTrue(app.contains("ApplicationModel.live()"))
        XCTAssertTrue(window.contains(".task(id: model.launchAttempt)"))

        let editorRegion = try XCTUnwrap(window.range(of: "case .editor:"))
        let bannerRegion = try XCTUnwrap(window.range(of: "case .errorBanner:"))
        let editorSlice = window[editorRegion.lowerBound..<bannerRegion.lowerBound]
        let restoring = try XCTUnwrap(editorSlice.range(of: "case .restoring:"))
        let failed = try XCTUnwrap(editorSlice.range(of: "case .failed"))
        let ready = try XCTUnwrap(editorSlice.range(of: "case .ready:"))
        let restoringSlice = editorSlice[restoring.lowerBound..<failed.lowerBound]
        let failedSlice = editorSlice[failed.lowerBound..<ready.lowerBound]
        let readySlice = editorSlice[ready.lowerBound..<editorSlice.endIndex]
        XCTAssertFalse(restoringSlice.contains("EditorHost"))
        XCTAssertFalse(failedSlice.contains("EditorHost"))
        XCTAssertTrue(readySlice.contains("EditorHost"))
        XCTAssertTrue(readySlice.contains("onEdit: model.handleCurrentDocumentEdit"))
        XCTAssertTrue(
            readySlice.contains("onStateChange: model.handleCurrentDocumentStateChange")
        )
    }

    func testProductionPresentsEveryDocumentDecisionThroughOneSheet() throws {
        let app = try contents(at: "Scratchpad/App/ScratchpadApp.swift")

        XCTAssertTrue(app.contains(".sheet("))
        XCTAssertTrue(app.contains("model.pendingDecision"))
        XCTAssertTrue(app.contains("model.resolvePendingDecision"))
        XCTAssertTrue(app.contains("case .replaceCurrentDocument, .closeWindow, .terminateApplication:"))
        XCTAssertTrue(app.contains("Button(\"Save\")"))
        XCTAssertTrue(app.contains("Button(\"Discard\", role: .destructive)"))
        XCTAssertTrue(app.contains("case .resolveConflict:"))
        XCTAssertTrue(app.contains("Button(\"Overwrite\", role: .destructive)"))
        XCTAssertTrue(app.contains("Button(\"Reload\")"))
        XCTAssertTrue(app.contains("Button(\"Save As\")"))
        XCTAssertTrue(app.contains("case .recreateDeletedFile:"))
        XCTAssertTrue(app.contains("Button(\"Recreate\", role: .destructive)"))
        XCTAssertTrue(app.contains("Button(\"Cancel\", role: .cancel)"))
    }
}
