import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class ThemeDefinitionTests: XCTestCase {
    func testSystemThemeResolvesFromEffectiveAppearance() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        XCTAssertEqual(
            ThemeDefinition.resolve(.system, effectiveAppearance: lightAppearance),
            ThemeDefinition.resolve(.light, effectiveAppearance: darkAppearance)
        )
        XCTAssertEqual(
            ThemeDefinition.resolve(.system, effectiveAppearance: darkAppearance),
            ThemeDefinition.resolve(.dark, effectiveAppearance: lightAppearance)
        )
        XCTAssertEqual(
            ThemeDefinition.resolve(.light, effectiveAppearance: lightAppearance),
            ThemeDefinition.resolve(.light, effectiveAppearance: darkAppearance)
        )
        XCTAssertEqual(
            ThemeDefinition.resolve(.dark, effectiveAppearance: lightAppearance),
            ThemeDefinition.resolve(.dark, effectiveAppearance: darkAppearance)
        )
    }

    func testLightThemeUsesApprovedNotoPalette() throws {
        let theme = ThemeDefinition.resolve(
            .light,
            effectiveAppearance: try XCTUnwrap(NSAppearance(named: .darkAqua))
        )

        assertColor(theme.editorBackground, hex: 0xFBFBFC)
        assertColor(theme.editorForeground, hex: 0x171717)
        assertColor(theme.caret, hex: 0x171717)
        assertColor(theme.titleRegion, hex: 0xF8F7FA)
        assertColor(theme.separator, hex: 0xD8D8DC)
        assertColor(theme.informationBar, hex: 0xF4F4F5)
        assertColor(theme.mutedText, hex: 0x6F6F73)
        assertColor(theme.banner, hex: 0xFFF3CD)
    }

    func testDarkThemeUsesApprovedCharcoalPalette() throws {
        let theme = ThemeDefinition.resolve(
            .dark,
            effectiveAppearance: try XCTUnwrap(NSAppearance(named: .aqua))
        )

        assertColor(theme.editorBackground, hex: 0x2B2B2B)
        assertColor(theme.editorForeground, hex: 0xE7E7E7)
        assertColor(theme.caret, hex: 0xE7E7E7)
        assertColor(theme.titleRegion, hex: 0x2B2B2B)
        assertColor(theme.separator, hex: 0x414141)
        assertColor(theme.informationBar, hex: 0x252525)
        assertColor(theme.mutedText, hex: 0xA2A2A2)
        assertColor(theme.banner, hex: 0x4A3D20)
    }

    func testEveryThemeMeetsTextSelectionAndMutedTextContrastChecks() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        for preference in AppearancePreference.allCases {
            for appearance in [lightAppearance, darkAppearance] {
                let style = ResolvedEditorStyle(
                    settings: settings(appearance: preference),
                    effectiveAppearance: appearance
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(style.theme.editorForeground, style.theme.editorBackground),
                    7
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(style.theme.mutedText, style.theme.editorBackground),
                    4.5
                )
                XCTAssertGreaterThanOrEqual(
                    contrast(style.selectionForeground, style.theme.selection),
                    4.5
                )
            }
        }
    }

    func testMissingFontResolvesToSFMono15() throws {
        let style = ResolvedEditorStyle(
            settings: settings(font: FontPreference(
                postScriptName: "DefinitelyUnavailable-Scratchpad",
                pointSize: 72
            )),
            effectiveAppearance: try XCTUnwrap(NSAppearance(named: .aqua))
        )

        XCTAssertEqual(
            style.font.fontName,
            NSFont.monospacedSystemFont(ofSize: 15, weight: .regular).fontName
        )
        XCTAssertEqual(style.font.pointSize, 15)
    }

    func testApplyingStyleDoesNotChangeTextGenerationOrUndoStack() throws {
        let document = DocumentSession(text: "styled text")
        document.storage.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 6)
        )
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        let textView = try XCTUnwrap(scrollView.documentView as? ScratchTextView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 4))
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.registerUndo(withTarget: document) { _ in }
        undoManager.setActionName("Existing Action")
        let originalString = document.storage.string
        let originalGeneration = document.generation
        let originalSelection = textView.selectedRange()
        let originalUndoActionName = undoManager.undoActionName
        let style = ResolvedEditorStyle(
            settings: settings(appearance: .dark),
            effectiveAppearance: try XCTUnwrap(NSAppearance(named: .darkAqua))
        )

        textView.apply(style: style)
        textView.apply(style: style)

        XCTAssertEqual(document.storage.string, originalString)
        XCTAssertEqual(document.generation, originalGeneration)
        XCTAssertEqual(textView.selectedRange(), originalSelection)
        XCTAssertEqual(undoManager.undoActionName, originalUndoActionName)
        XCTAssertTrue(undoManager.canUndo)
    }

    func testEditorStyleConfiguresWrapLineHeightAndNativeTextOptions() throws {
        let document = DocumentSession(text: "alpha")
        let coordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(document: document, coordinator: coordinator)
        let textView = try XCTUnwrap(scrollView.documentView as? ScratchTextView)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let style = ResolvedEditorStyle(
            settings: settings(
                smartSubstitutionsEnabled: true,
                spellingEnabled: true,
                insertsSpaces: true,
                tabWidth: 6,
                keepsIndentation: false,
                appearance: .light
            ),
            effectiveAppearance: try XCTUnwrap(NSAppearance(named: .aqua))
        )

        textView.apply(style: style)

        XCTAssertEqual(textView.font, style.font)
        XCTAssertEqual(textView.textColor, style.theme.editorForeground)
        XCTAssertEqual(textView.backgroundColor, style.theme.editorBackground)
        XCTAssertEqual(textView.insertionPointColor, style.theme.caret)
        XCTAssertEqual(textView.selectedTextAttributes[.backgroundColor] as? NSColor, style.theme.selection)
        XCTAssertEqual(textView.selectedTextAttributes[.foregroundColor] as? NSColor, style.selectionForeground)
        XCTAssertEqual(textView.textContainerInset, NSSize(width: 24, height: 20))
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertTrue(textContainer.widthTracksTextView)
        XCTAssertTrue(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertTrue(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertTrue(textView.isContinuousSpellCheckingEnabled)
        XCTAssertTrue(textView.isAutomaticSpellingCorrectionEnabled)
        XCTAssertEqual(
            try XCTUnwrap(textView.defaultParagraphStyle).lineHeightMultiple,
            1.45,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(textView.defaultParagraphStyle?.defaultTabInterval ?? 0, 0)
        XCTAssertEqual(textView.commandContext.indentationUnit, "      ")
        XCTAssertEqual(textView.commandContext.tabWidth, 6)
        XCTAssertFalse(textView.commandContext.keepsIndentation)
    }

    private func settings(
        font: FontPreference = FontPreference(postScriptName: "SFMono-Regular", pointSize: 15),
        smartSubstitutionsEnabled: Bool = false,
        spellingEnabled: Bool = false,
        insertsSpaces: Bool = false,
        tabWidth: Int = 4,
        keepsIndentation: Bool = true,
        appearance: AppearancePreference = .system
    ) -> EditorSettingsSnapshot {
        EditorSettingsSnapshot(
            font: font,
            smartSubstitutionsEnabled: smartSubstitutionsEnabled,
            spellingEnabled: spellingEnabled,
            insertsSpaces: insertsSpaces,
            tabWidth: tabWidth,
            keepsIndentation: keepsIndentation,
            countsWhitespace: false,
            showsInformationBar: true,
            appearance: appearance
        )
    }

    private func assertColor(
        _ color: NSColor,
        hex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            XCTFail("Color is not convertible to device RGB", file: file, line: line)
            return
        }
        XCTAssertEqual(rgb.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(rgb.alphaComponent, 1, accuracy: 0.005, file: file, line: line)
    }

    private func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            XCTFail("Color is not convertible to device RGB")
            return 0
        }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }
}
