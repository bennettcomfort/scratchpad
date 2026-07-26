import Darwin
import Foundation
import XCTest

@MainActor
final class PerformanceUITests: XCTestCase {
    private var testRoot: URL!

    func testOneMegabyteRestoredLaunchUsesApplicationLaunchMetric() {
        prepareRestoredDocument(byteCount: 1_000_000)
        defer { removeTestRoot() }
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        var launchDurations: [Double] = []

        measure(
            metrics: [
                XCTApplicationLaunchMetric(),
                XCTOSSignpostMetric(
                    subsystem: "com.scratchpad.app",
                    category: "PointsOfInterest",
                    name: "launchToEditorReady"
                ),
            ],
            options: options
        ) {
            let app = configuredApplication()
            app.launch()
            let duration = app.staticTexts["launch-duration"]
            XCTAssertTrue(duration.waitForExistence(timeout: 5))
            if let value = duration.value as? String,
               let milliseconds = Double(value) {
                launchDurations.append(milliseconds)
            }
        }

        let measuredDurations = Array(launchDurations.suffix(5)).sorted()
        guard measuredDurations.count == 5 else {
            XCTFail("Expected five launch-duration samples, got \(measuredDurations.count)")
            return
        }
        XCTAssertLessThan(measuredDurations[2], 1_200)
    }

    func testTwoMegabyteTypingRecordsNoHitchesAtTargetRefreshRate() {
        prepareRestoredDocument(byteCount: 2_000_000)
        let app = configuredApplication()
        app.launch()
        defer {
            app.terminate()
            removeTestRoot()
        }
        app.typeText("w")
        app.typeKey("z", modifierFlags: .command)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(
            metrics: [XCTHitchMetric(application: app)],
            options: options
        ) {
            app.typeText(String(repeating: "x", count: 120))
        }
    }

    private func configuredApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCRATCHPAD_UI_TEST_ROOT"] = testRoot.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = testRoot.path
        return app
    }

    private func prepareRestoredDocument(byteCount: Int) {
        let userHome: URL
        if let passwordEntry = getpwuid(getuid()) {
            userHome = URL(
                filePath: String(cString: passwordEntry.pointee.pw_dir),
                directoryHint: .isDirectory
            )
        } else {
            userHome = FileManager.default.homeDirectoryForCurrentUser
        }
        testRoot = userHome.appending(
            path: "Library/Containers/com.scratchpad.app/Data/tmp/"
                + "ScratchpadPerformanceUITests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        let seedApp = configuredApplication()
        seedApp.launchEnvironment[
            "SCRATCHPAD_UI_TEST_SEED_DOCUMENT_BYTES"
        ] = String(byteCount)
        seedApp.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        seedApp.terminate()
        XCTAssertTrue(waitUntil { seedApp.state == .notRunning })
    }

    private func removeTestRoot() {
        if let testRoot {
            try? FileManager.default.removeItem(at: testRoot)
        }
        testRoot = nil
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
