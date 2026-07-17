import Darwin
import Foundation
import XCTest

@MainActor
final class AccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!
    private var testRoot: URL!

    func testLaunchPlacesKeyboardFocusInEditor() {
        startApp()
        defer { stopApp() }
        let editor = element("editor")

        XCTAssertTrue(editor.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(hasKeyboardFocus(editor))
    }

    func testTitleReportsFilenameAndEditedState() {
        startApp()
        defer { stopApp() }
        let editor = element("editor")
        let title = element("document-title")

        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Untitled")
        XCTAssertEqual(title.value as? String, "Saved")

        editor.typeText("Edited text")

        XCTAssertTrue(waitUntil { title.label == "Untitled — Edited" })
        XCTAssertEqual(title.value as? String, "Edited")
    }

    func testInformationBarExposesMetricsEncodingAndTokenHelp() {
        startApp()
        defer { stopApp() }
        let editor = element("editor")
        let informationBar = element("information-bar")

        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("one two")
        XCTAssertTrue(informationBar.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil {
            (informationBar.value as? String)?.contains("2 words") == true
        })
        XCTAssertTrue((informationBar.value as? String)?.contains("Unicode (UTF-8)") == true)
        XCTAssertTrue((informationBar.value as? String)?.contains("tokens") == true)
        XCTAssertTrue(
            (informationBar.value as? String)?.contains(
                "Estimated token count. Exact counts vary by model."
            ) == true
        )
    }

    func testBannerActionsHaveUniqueLabelsAndKeyboardFocus() {
        startApp(environment: ["SCRATCHPAD_UI_TEST_FORCE_BANNER": "1"])
        defer { stopApp() }

        let banner = element("error-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        let retry = app.buttons["Retry"]
        let dismiss = app.buttons["Dismiss"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(dismiss.exists)
        XCTAssertNotEqual(retry.label, dismiss.label)
        XCTAssertTrue(waitUntil { [retry, dismiss].contains(where: hasKeyboardFocus) })
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(waitUntil { !banner.exists })
    }

    func testDecisionSheetHasCorrectDefaultAndCancelButtons() {
        startApp()
        defer { stopApp() }
        let editor = element("editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Unsaved")

        app.typeKey("n", modifierFlags: .command)
        let sheet = element("decision-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil { !sheet.exists })
        XCTAssertTrue(hasKeyboardFocus(editor))

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.windows["save-panel"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
    }

    func testSettingsTabsAndControlsHaveUniqueLabels() {
        startApp()
        defer { stopApp() }
        openSettings()

        let general = app.buttons["General"]
        let editor = app.buttons["Editor"]
        let theme = app.buttons["Theme"]
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.exists)
        XCTAssertTrue(theme.exists)
        XCTAssertEqual(Set([general.title, editor.title, theme.title]).count, 3)

        assertExists(["settings-launch-at-login", "settings-open-recovery-folder"])
        editor.click()
        assertExists([
            "settings-choose-font",
            "settings-smart-substitutions",
            "settings-spelling-and-correction",
            "settings-spaces-instead-of-tabs",
            "settings-tab-width",
            "settings-keep-indentation",
            "settings-count-whitespace",
            "settings-information-bar",
        ])
        theme.click()
        assertExists(["settings-appearance", "settings-preview"])
    }

    func testFullKeyboardAccessReachesEveryInteractiveControl() {
        startApp()
        defer { stopApp() }
        openSettings()
        let launchAtLogin = element("settings-launch-at-login")

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.windows["Editor"].waitForExistence(timeout: 5))
        let chooseFont = element("settings-choose-font")
        XCTAssertTrue(chooseFont.waitForExistence(timeout: 5))
        XCTAssertTrue(tabUntilFocused(chooseFont))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.windows.matching(NSPredicate(format: "title CONTAINS[c] 'font'")).firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        assertKeyboardToggle("settings-smart-substitutions")
        assertKeyboardToggle("settings-spelling-and-correction")
        assertKeyboardToggle("settings-spaces-instead-of-tabs")

        let tabWidth = element("settings-tab-width")
        XCTAssertTrue(tabUntilFocused(tabWidth))
        let originalTabWidth = String(describing: tabWidth.value)
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil { String(describing: tabWidth.value) != originalTabWidth })

        assertKeyboardToggle("settings-keep-indentation")
        assertKeyboardToggle("settings-count-whitespace")
        assertKeyboardToggle("settings-information-bar")

        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.windows["Theme"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings-preview").waitForExistence(timeout: 5))
        let appearanceOptions = [
            app.radioButtons["System"],
            app.radioButtons["Light"],
            app.radioButtons["Dark"],
        ]
        XCTAssertTrue(tabUntilAnyFocused(appearanceOptions))
        let originalFocusedAppearance = appearanceOptions.first(where: hasKeyboardFocus)?.label
        let originalAppearanceValues = appearanceOptions.map { String(describing: $0.value) }
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            appearanceOptions.first(where: hasKeyboardFocus)?.label != originalFocusedAppearance
        })
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            appearanceOptions.map { String(describing: $0.value) } != originalAppearanceValues
        })

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.windows["General"].waitForExistence(timeout: 5))
        XCTAssertTrue(launchAtLogin.waitForExistence(timeout: 5))
        XCTAssertTrue(tabUntilFocused(launchAtLogin))
        let originalLaunchAtLoginValue = String(describing: launchAtLogin.value)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(waitUntil {
            String(describing: launchAtLogin.value) != originalLaunchAtLoginValue
        })

        let openRecoveryFolder = element("settings-open-recovery-folder")
        XCTAssertTrue(tabUntilFocused(openRecoveryFolder))
        app.typeKey(.space, modifierFlags: [])
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        XCTAssertTrue(waitUntil { finder.state == .runningForeground })
        app.activate()
    }

    private func assertKeyboardToggle(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let toggle = element(identifier)
        XCTAssertTrue(toggle.exists, identifier, file: file, line: line)
        XCTAssertTrue(tabUntilFocused(toggle), identifier, file: file, line: line)
        let originalValue = String(describing: toggle.value)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(
            waitUntil { String(describing: toggle.value) != originalValue },
            identifier,
            file: file,
            line: line
        )
    }

    func testNativeFindAndServicesRemainReachable() {
        startApp()
        defer { stopApp() }
        let editor = element("editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        app.menuBars.menuBarItems["Scratchpad"].click()
        let services = app.menuItems["Services"]
        XCTAssertTrue(services.exists)
        XCTAssertTrue(services.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    private func openSettings() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.buttons["General"].waitForExistence(timeout: 5))
    }

    private func startApp(environment: [String: String] = [:]) {
        continueAfterFailure = false
        let userHome: URL
        if let passwordEntry = getpwuid(getuid()) {
            userHome = URL(
                filePath: String(cString: passwordEntry.pointee.pw_dir),
                directoryHint: .isDirectory
            )
        } else {
            userHome = FileManager.default.homeDirectoryForCurrentUser
        }
        let containerTemporaryDirectory = userHome
            .appending(path: "Library/Containers/com.scratchpad.app/Data/tmp", directoryHint: .isDirectory)
        testRoot = containerTemporaryDirectory.appending(
            path: "ScratchpadUITests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(
            at: testRoot,
            withIntermediateDirectories: true
        )
        app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3",
        ]
        app.launchEnvironment["SCRATCHPAD_UI_TEST_ROOT"] = testRoot.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = testRoot.path
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        app.activate()
    }

    private func stopApp() {
        app?.terminate()
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        app = nil
        testRoot = nil
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func assertExists(_ identifiers: [String], file: StaticString = #filePath, line: UInt = #line) {
        for identifier in identifiers {
            XCTAssertTrue(element(identifier).exists, identifier, file: file, line: line)
        }
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        element.value(forKey: "hasKeyboardFocus") as? Bool == true
    }

    private func tabUntilFocused(_ element: XCUIElement, maximumTabs: Int = 12) -> Bool {
        if hasKeyboardFocus(element) { return true }
        for _ in 0..<maximumTabs {
            app.typeKey(.tab, modifierFlags: [])
            if hasKeyboardFocus(element) { return true }
        }
        return false
    }

    private func tabUntilAnyFocused(
        _ elements: [XCUIElement],
        maximumTabs: Int = 12
    ) -> Bool {
        if elements.contains(where: hasKeyboardFocus) { return true }
        for _ in 0..<maximumTabs {
            app.typeKey(.tab, modifierFlags: [])
            if elements.contains(where: hasKeyboardFocus) { return true }
        }
        return false
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }
}
