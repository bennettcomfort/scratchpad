import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class PresentationModelTests: XCTestCase {
    func testTitlePresentsUntitledFilenameAndEditedSuffixExactly() {
        XCTAssertEqual(
            DocumentTitlePresentation(displayName: "Untitled", hasUnsavedChanges: false).title,
            "Untitled"
        )
        XCTAssertEqual(
            DocumentTitlePresentation(displayName: "Untitled", hasUnsavedChanges: true).title,
            "Untitled — Edited"
        )
        XCTAssertEqual(
            DocumentTitlePresentation(displayName: "prompt.md", hasUnsavedChanges: false).title,
            "prompt.md"
        )
        XCTAssertEqual(
            DocumentTitlePresentation(displayName: "prompt.md", hasUnsavedChanges: true).title,
            "prompt.md — Edited"
        )

        let deletedContent = DocumentTitlePresentation(
            displayName: "prompt.md",
            hasUnsavedChanges: true
        )
        XCTAssertEqual(deletedContent.accessibilityValue, "Edited")
    }

    func testInformationBarFormatsRequiredMetricsAndUTF8Label() {
        let presentation = InformationBarPresentation(
            metrics: DocumentMetrics(
                characters: 72,
                words: 14,
                lines: 8,
                estimatedTokens: 21,
                isEstimate: true
            )
        )

        XCTAssertEqual(
            presentation.metricsText,
            "72 characters · 14 words · 8 lines · ~21 tokens"
        )
        XCTAssertEqual(presentation.encodingText, "Unicode (UTF-8)")
    }

    func testTokenHelpTextStatesEstimateVariesByModel() {
        XCTAssertEqual(
            InformationBarPresentation.tokenHelpText,
            "Estimated token count. Exact counts vary by model."
        )
    }

    func testInformationBarVisibilityChangesOnlyTheBottomTwentyEightPoints() {
        let visible = MainWindowPresentation(showsInformationBar: true, hasErrorBanner: false)
        let hidden = MainWindowPresentation(showsInformationBar: false, hasErrorBanner: false)

        XCTAssertEqual(visible.titleRegionHeight, 44)
        XCTAssertEqual(hidden.titleRegionHeight, 44)
        XCTAssertEqual(visible.separatorHeight, 1)
        XCTAssertEqual(hidden.separatorHeight, 1)
        XCTAssertEqual(visible.informationBarHeight, 28)
        XCTAssertEqual(hidden.informationBarHeight, 0)
        XCTAssertEqual(visible.fixedHeight - hidden.fixedHeight, 28)
    }

    func testWindowUsesRequiredDefaultMinimumAndRestoredFrame() {
        XCTAssertEqual(WindowChromeConfiguration.defaultSize, NSSize(width: 820, height: 640))
        XCTAssertEqual(WindowChromeConfiguration.minimumSize, NSSize(width: 480, height: 320))

        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let restored = NSRect(x: 100, y: 100, width: 900, height: 700)
        XCTAssertEqual(
            WindowChromeConfiguration.targetFrame(
                restoredFrame: restored,
                currentScreenFrames: [screen]
            ),
            restored
        )

        XCTAssertEqual(
            WindowChromeConfiguration.targetFrame(
                restoredFrame: NSRect(x: 2_000, y: 2_000, width: 900, height: 700),
                currentScreenFrames: [screen]
            ),
            NSRect(x: 310, y: 130, width: 820, height: 640)
        )
    }

    func testWindowHierarchyContainsNoDeferredChrome() {
        XCTAssertEqual(
            MainWindowPresentation(showsInformationBar: true, hasErrorBanner: true).hierarchy,
            [.titleRegion, .editor, .errorBanner, .separator, .informationBar]
        )
        XCTAssertTrue(MainWindowPresentation.deferredChrome.isEmpty)
    }
}
