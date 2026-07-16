import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class FontPanelCoordinatorTests: XCTestCase {
    func testFontPanelConvertsAndPersistsSelectedFont() throws {
        let fixture = try SettingsFixture()
        defer { fixture.remove() }
        let manager = FontManagerFake()
        let initialFont = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 15))
        fixture.store.setFont(
            FontPreference(postScriptName: initialFont.fontName, pointSize: initialFont.pointSize)
        )
        manager.convertedFont = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 18))
        let coordinator = FontPanelCoordinator(settings: fixture.store, fontManager: manager)

        coordinator.open()
        coordinator.changeFont(nil)

        XCTAssertEqual(manager.selectedFont?.fontName, initialFont.fontName)
        XCTAssertEqual(manager.selectedFont?.pointSize, 15)
        XCTAssertEqual(manager.selectedFontIsMultiple, false)
        XCTAssertEqual(manager.orderFrontCount, 1)
        XCTAssertEqual(
            fixture.store.snapshot.font,
            FontPreference(postScriptName: manager.convertedFont.fontName, pointSize: 18)
        )
    }

    func testFontPanelRestoresPreviousTargetAndActionOnClose() throws {
        let fixture = try SettingsFixture()
        defer { fixture.remove() }
        let manager = FontManagerFake()
        let priorTarget = FontTarget()
        manager.target = priorTarget
        manager.action = #selector(FontTarget.previousAction(_:))
        let coordinator = FontPanelCoordinator(settings: fixture.store, fontManager: manager)

        coordinator.open()
        XCTAssertTrue(manager.target === coordinator)
        XCTAssertEqual(manager.action, #selector(FontPanelCoordinator.changeFont(_:)))

        coordinator.close()

        XCTAssertTrue(manager.target === priorTarget)
        XCTAssertEqual(manager.action, #selector(FontTarget.previousAction(_:)))
    }

    func testGeneralPresentationContainsOnlyLaunchAndRecoveryFolderActions() {
        XCTAssertEqual(
            GeneralSettingsPresentation.controls,
            [.launchAtLogin, .openRecoveryFolder]
        )
        XCTAssertTrue(
            Set(GeneralSettingsPresentation.controls.map(\.rawValue))
                .isDisjoint(with: ["recoveryToggle", "customShortcutEditor", "pluginControl"])
        )
        XCTAssertTrue(GeneralSettingsPresentation.deferredControls.isEmpty)
    }

    func testEditorPresentationMatchesAllEightSpecifiedControlsAndRanges() {
        XCTAssertEqual(
            EditorSettingsPresentation.controls,
            [
                .chooseFont,
                .smartSubstitutions,
                .spellingAndCorrection,
                .spacesInsteadOfTabs,
                .tabWidth,
                .keepIndentation,
                .countWhitespace,
                .informationBar,
            ]
        )
        XCTAssertEqual(EditorSettingsPresentation.tabWidthRange, 1...8)
        XCTAssertTrue(
            Set(EditorSettingsPresentation.controls.map(\.rawValue))
                .isDisjoint(with: ["informationHUD", "customShortcutEditor", "pluginControl"])
        )
        XCTAssertTrue(EditorSettingsPresentation.deferredControls.isEmpty)
    }

    func testThemePresentationContainsOnlySystemLightAndDark() {
        XCTAssertEqual(ThemeSettingsPresentation.appearances, [.system, .light, .dark])
        XCTAssertFalse(ThemeSettingsPresentation.isPreviewEditable)
        XCTAssertTrue(
            Set(ThemeSettingsPresentation.deferredControls)
                .isDisjoint(with: ["informationHUD", "themeColorWell", "pluginControl"])
        )
        XCTAssertTrue(ThemeSettingsPresentation.deferredControls.isEmpty)
    }

    func testThemePreviewNeverMutatesEditorOrSettings() throws {
        let fixture = try SettingsFixture()
        defer { fixture.remove() }
        let document = DocumentSession(text: "\tunchanged text")
        let originalText = document.storage.string
        let originalGeneration = document.generation
        let originalSnapshot = fixture.store.snapshot
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        _ = ThemePreviewPresentation(
            settings: fixture.store.snapshot,
            effectiveAppearance: appearance
        )

        XCTAssertEqual(document.storage.string, originalText)
        XCTAssertEqual(document.generation, originalGeneration)
        XCTAssertEqual(fixture.store.snapshot, originalSnapshot)
    }
}

@MainActor
private final class FontManagerFake: FontManaging {
    weak var target: AnyObject?
    var action = NSSelectorFromString("changeFont:")
    var convertedFont = NSFont.systemFont(ofSize: 12)
    private(set) var selectedFont: NSFont?
    private(set) var selectedFontIsMultiple: Bool?
    private(set) var orderFrontCount = 0

    func setSelectedFont(_ font: NSFont, isMultiple: Bool) {
        selectedFont = font
        selectedFontIsMultiple = isMultiple
    }

    func orderFrontFontPanel(_ sender: Any?) {
        orderFrontCount += 1
    }

    func convert(_ font: NSFont) -> NSFont {
        convertedFont
    }
}

@MainActor
private final class FontTarget: NSObject {
    @objc func previousAction(_ sender: Any?) {}
}

@MainActor
private struct SettingsFixture {
    let defaults: UserDefaults
    let suiteName: String
    let store: SettingsStore

    init() throws {
        suiteName = "FontPanelCoordinatorTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        store = SettingsStore(defaults: defaults, launchService: LaunchServiceFake())
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class LaunchServiceFake: LaunchAtLoginServicing {
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
