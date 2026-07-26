import Foundation
import XCTest

final class ReleasePolicyTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func appSourceEntries() throws -> [String] {
        let specification = try contents(at: "project.yml")
        let targetStart = try XCTUnwrap(specification.range(of: "  Scratchpad:\n"))
        let testsStart = try XCTUnwrap(
            specification.range(
                of: "  ScratchpadTests:\n",
                range: targetStart.upperBound..<specification.endIndex
            )
        )
        let target = specification[targetStart.upperBound..<testsStart.lowerBound]
        let sourcesStart = try XCTUnwrap(target.range(of: "    sources:\n"))
        let settingsStart = try XCTUnwrap(
            target.range(
                of: "    settings:\n",
                range: sourcesStart.upperBound..<target.endIndex
            )
        )

        return target[sourcesStart.upperBound..<settingsStart.lowerBound]
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: CharacterSet.whitespaces)
                guard trimmed.hasPrefix("- ") else { return nil }
                let value = String(trimmed.dropFirst(2))
                return value.hasPrefix("path: ")
                    ? String(value.dropFirst("path: ".count))
                    : value
            }
    }

    func testActiveSourcesContainNoHardInvariantViolations() throws {
        let approvedSources: Set<String> = [
            "Scratchpad/App/AppCommands.swift",
            "Scratchpad/App/AppDelegate.swift",
            "Scratchpad/App/ApplicationModel.swift",
            "Scratchpad/App/ApplicationServices.swift",
            "Scratchpad/App/DocumentDecisionCoordinator.swift",
            "Scratchpad/App/FilePanelProvider.swift",
            "Scratchpad/App/LifecycleCoordinators.swift",
            "Scratchpad/App/MainWindowView.swift",
            "Scratchpad/App/ScratchpadApp.swift",
            "Scratchpad/Document/DocumentSession.swift",
            "Scratchpad/Document/DocumentMetrics.swift",
            "Scratchpad/Document/MetricsCoordinator.swift",
            "Scratchpad/Document/DocumentSnapshot.swift",
            "Scratchpad/Document/DocumentState.swift",
            "Scratchpad/Editor/EditorCoordinator.swift",
            "Scratchpad/Editor/EditorCommand.swift",
            "Scratchpad/Editor/EditorCommandRouter.swift",
            "Scratchpad/Editor/EditorHost.swift",
            "Scratchpad/Editor/LineTable.swift",
            "Scratchpad/Editor/ScratchTextView.swift",
            "Scratchpad/Files/FileModels.swift",
            "Scratchpad/Files/FileResults.swift",
            "Scratchpad/Files/ExternalChangeMonitor.swift",
            "Scratchpad/Files/FileService.swift",
            "Scratchpad/Persistence/ApplicationSupportPaths.swift",
            "Scratchpad/Persistence/AtomicFileWriter.swift",
            "Scratchpad/Persistence/BookmarkStore.swift",
            "Scratchpad/Persistence/PersistenceRecords.swift",
            "Scratchpad/Persistence/RecoveryCoordinator.swift",
            "Scratchpad/Persistence/SessionRepository.swift",
            "Scratchpad/Settings/LaunchAtLoginService.swift",
            "Scratchpad/Settings/FontPanelCoordinator.swift",
            "Scratchpad/Settings/SettingsStore.swift",
            "Scratchpad/Settings/SettingsView.swift",
            "Scratchpad/Settings/ThemeDefinition.swift",
            "Scratchpad/UI/DocumentTitleView.swift",
            "Scratchpad/UI/ErrorBannerView.swift",
            "Scratchpad/UI/InformationBarView.swift",
            "Scratchpad/UI/ThemePreviewView.swift",
            "Scratchpad/UI/WindowChromeConfigurator.swift",
            "Scratchpad/Utilities/ContentHash.swift",
            "Scratchpad/Utilities/Log.swift",
            "Scratchpad/Utilities/PerformanceProbe.swift"
        ]
        let activeSources = try appSourceEntries().filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(activeSources.isEmpty)
        XCTAssertEqual(Set(activeSources), approvedSources)

        let forceUnwrap = try NSRegularExpression(
            pattern: #"(?:\$[0-9]+|[A-Za-z_][A-Za-z0-9_]*|\)|\])!\s*(?![=])"#,
            options: [.anchorsMatchLines]
        )
        let textState = try NSRegularExpression(
            pattern: #"@State(?:\s+private)?\s+var\s+(?:(?:text|content|prompt|documentText)\b|\w+(?:\s*:\s*String\b|\s*=\s*(?:#?\"|String\s*\(|[^\n]*(?:\.text|\.string)\b)))"#
        )
        let directPathHintURL = try NSRegularExpression(
            pattern: #"URL\s*\(\s*file(?:URLWith)?Path\s*:\s*pathHint\s*\)"#
        )
        let defaultsNotification = try NSRegularExpression(
            pattern: #"NotificationCenter\s*\.\s*default\s*\.\s*post\b"#
        )
        let printCall = try NSRegularExpression(pattern: #"\bprint\s*\("#)
        let scannerFixtures: [(NSRegularExpression, String)] = [
            (forceUnwrap, "value!.property"),
            (forceUnwrap, "value! + 1"),
            (forceUnwrap, "$0!.property"),
            (textState, "@State private var prompt = \"\""),
            (textState, "@State private var draft = model.text"),
            (directPathHintURL, "URL ( filePath: pathHint )"),
            (defaultsNotification, "NotificationCenter.default.post(name: event)"),
            (printCall, "print (message)")
        ]
        for (scanner, fixture) in scannerFixtures {
            XCTAssertNotNil(
                scanner.firstMatch(
                    in: fixture,
                    range: NSRange(fixture.startIndex..., in: fixture)
                ),
                fixture
            )
        }

        for path in activeSources {
            let source = try contents(at: path)
            let range = NSRange(source.startIndex..., in: source)

            XCTAssertFalse(source.contains(".layoutManager"), path)
            XCTAssertFalse(source.contains("try!"), path)
            XCTAssertNil(forceUnwrap.firstMatch(in: source, range: range), path)
            XCTAssertNil(textState.firstMatch(in: source, range: range), path)
            XCTAssertNil(directPathHintURL.firstMatch(in: source, range: range), path)
            XCTAssertNil(defaultsNotification.firstMatch(in: source, range: range), path)
            XCTAssertNil(printCall.firstMatch(in: source, range: range), path)
        }
    }

    func testGeneratedTargetContainsNoDeferredFeatureSource() throws {
        let project = try contents(at: "Scratchpad.xcodeproj/project.pbxproj").lowercased()
        let activeSources = try appSourceEntries()
        for path in activeSources where path.hasSuffix(".swift") {
            let sourceName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            XCTAssertTrue(project.contains(sourceName), path)
        }

        let allSwiftSources = FileManager.default.enumerator(
            at: repositoryRoot.appendingPathComponent("Scratchpad"),
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let activeNames = Set(activeSources.map {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased()
        })
        for source in allSwiftSources where !activeNames.contains(source.lastPathComponent.lowercased()) {
            XCTAssertFalse(project.contains(source.lastPathComponent.lowercased()), source.path)
        }
    }

    func testReleaseEntitlementsAreSandboxedAndNetworkFree() throws {
        let entitlementSettings = try contents(at: "project.yml")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("CODE_SIGN_ENTITLEMENTS:") }
        XCTAssertEqual(
            entitlementSettings,
            ["CODE_SIGN_ENTITLEMENTS: Scratchpad/App/Scratchpad.entitlements"]
        )

        let data = try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("Scratchpad/App/Scratchpad.entitlements")
        )
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(value as? [String: Any])
        let expectedKeys: Set<String> = [
            "com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.files.bookmarks.app-scope"
        ]

        XCTAssertEqual(Set(entitlements.keys), expectedKeys)
        for key in expectedKeys {
            XCTAssertEqual(entitlements[key] as? Bool, true, key)
        }
        XCTAssertNil(entitlements["com.apple.security.network.client"])
        XCTAssertNil(entitlements["com.apple.security.network.server"])
    }

    func testDependencyGraphContainsNoRuntimePackageProducts() throws {
        let specification = try contents(at: "project.yml")
        let project = try contents(at: "Scratchpad.xcodeproj/project.pbxproj")

        XCTAssertFalse(specification.contains("\npackages:"))
        XCTAssertFalse(project.contains("XCRemoteSwiftPackageReference"))
        XCTAssertFalse(project.contains("XCSwiftPackageProductDependency"))
    }
}
