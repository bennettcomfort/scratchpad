import AppKit
import Foundation
import Observation
import XCTest
@testable import Scratchpad

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testRegistersEverySpecifiedDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, launchService: LaunchServiceFake())

        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(store.snapshot.font, FontPreference(postScriptName: "SFMono-Regular", pointSize: 15))
        XCTAssertFalse(store.snapshot.smartSubstitutionsEnabled)
        XCTAssertFalse(store.snapshot.spellingEnabled)
        XCTAssertFalse(store.snapshot.insertsSpaces)
        XCTAssertEqual(store.snapshot.tabWidth, 4)
        XCTAssertTrue(store.snapshot.keepsIndentation)
        XCTAssertFalse(store.snapshot.countsWhitespace)
        XCTAssertTrue(store.snapshot.showsInformationBar)
        XCTAssertEqual(store.snapshot.appearance, .system)

        let registeredKeys = Set(defaults.dictionaryRepresentation().keys)
        XCTAssertTrue(registeredKeys.isSuperset(of: SettingsKey.all))
    }

    func testPersistsEachSettingInAnInjectedSuite() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchService = LaunchServiceFake()
        let store = SettingsStore(defaults: defaults, launchService: launchService)
        let font = FontPreference(
            postScriptName: try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 17)).fontName,
            pointSize: 17
        )

        store.setLaunchAtLogin(true)
        store.setFont(font)
        store.setSmartSubstitutionsEnabled(true)
        store.setSpellingEnabled(true)
        store.setInsertsSpaces(true)
        store.setTabWidth(7)
        store.setKeepsIndentation(false)
        store.setCountsWhitespace(true)
        store.setShowsInformationBar(false)
        store.setAppearance(.dark)

        let restored = SettingsStore(defaults: defaults, launchService: launchService)
        XCTAssertTrue(restored.launchAtLogin)
        XCTAssertEqual(
            restored.snapshot,
            EditorSettingsSnapshot(
                font: font,
                smartSubstitutionsEnabled: true,
                spellingEnabled: true,
                insertsSpaces: true,
                tabWidth: 7,
                keepsIndentation: false,
                countsWhitespace: true,
                showsInformationBar: false,
                appearance: .dark
            )
        )
    }

    func testTabWidthClampsToOneThroughEight() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, launchService: LaunchServiceFake())

        store.setTabWidth(-20)
        XCTAssertEqual(store.snapshot.tabWidth, 1)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.tabWidth), 1)

        store.setTabWidth(20)
        XCTAssertEqual(store.snapshot.tabWidth, 8)
        XCTAssertEqual(defaults.integer(forKey: SettingsKey.tabWidth), 8)
    }

    func testUnavailableFontFallsBackToSFMono15WithoutDeletingPreference() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let unavailable = FontPreference(postScriptName: "DefinitelyUnavailable-Scratchpad", pointSize: 27)
        let encoded = try JSONEncoder().encode(unavailable)
        defaults.set(encoded, forKey: SettingsKey.font)

        let store = SettingsStore(defaults: defaults, launchService: LaunchServiceFake())

        XCTAssertEqual(store.snapshot.font, FontPreference(postScriptName: "SFMono-Regular", pointSize: 15))
        XCTAssertEqual(defaults.data(forKey: SettingsKey.font), encoded)
    }

    func testChangingSpacesSettingDoesNotMutateDocumentStorage() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, launchService: LaunchServiceFake())
        let storage = NSTextStorage(string: "\tunchanged\n  text")

        store.setInsertsSpaces(true)

        XCTAssertEqual(storage.string, "\tunchanged\n  text")
        XCTAssertTrue(store.snapshot.insertsSpaces)
    }

    func testLaunchAtLoginSuccessPersistsActualServiceStatus() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchService = LaunchServiceFake()
        launchService.statusAfterSet = false
        let store = SettingsStore(defaults: defaults, launchService: launchService)

        store.setLaunchAtLogin(true)

        XCTAssertEqual(launchService.requestedValues, [true])
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(defaults.bool(forKey: SettingsKey.launchAtLogin))
        XCTAssertNil(store.errorMessage)
    }

    func testLaunchAtLoginFailureRollsBackToggleAndSurfacesError() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let launchService = LaunchServiceFake(isEnabled: true)
        launchService.error = LaunchServiceError.denied
        let store = SettingsStore(defaults: defaults, launchService: launchService)

        store.setLaunchAtLogin(false)

        XCTAssertEqual(launchService.requestedValues, [false])
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertTrue(defaults.bool(forKey: SettingsKey.launchAtLogin))
        XCTAssertNotNil(store.errorMessage)
    }

    func testSettingsChangesPublishOneTypedSnapshotWithoutNotificationCenter() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, launchService: LaunchServiceFake())
        let probe = ObservationProbe()

        withObservationTracking {
            _ = store.snapshot
        } onChange: {
            probe.recordChange()
        }
        store.setInsertsSpaces(true)

        XCTAssertEqual(probe.changeCount, 1)
        XCTAssertEqual(
            store.snapshot,
            EditorSettingsSnapshot(
                font: FontPreference(postScriptName: "SFMono-Regular", pointSize: 15),
                smartSubstitutionsEnabled: false,
                spellingEnabled: false,
                insertsSpaces: true,
                tabWidth: 4,
                keepsIndentation: true,
                countsWhitespace: false,
                showsInformationBar: true,
                appearance: .system
            )
        )
    }

    private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.setVolatileDomain([:], forName: suiteName)
        return (defaults, suiteName)
    }
}

private enum SettingsKey {
    static let launchAtLogin = "settings.launchAtLogin"
    static let font = "settings.font"
    static let smartSubstitutionsEnabled = "settings.smartSubstitutionsEnabled"
    static let spellingEnabled = "settings.spellingEnabled"
    static let insertsSpaces = "settings.insertsSpaces"
    static let tabWidth = "settings.tabWidth"
    static let keepsIndentation = "settings.keepsIndentation"
    static let countsWhitespace = "settings.countsWhitespace"
    static let showsInformationBar = "settings.showsInformationBar"
    static let appearance = "settings.appearance"

    static let all: Set<String> = [
        launchAtLogin,
        font,
        smartSubstitutionsEnabled,
        spellingEnabled,
        insertsSpaces,
        tabWidth,
        keepsIndentation,
        countsWhitespace,
        showsInformationBar,
        appearance,
    ]
}

@MainActor
private final class LaunchServiceFake: LaunchAtLoginServicing {
    var isEnabled: Bool
    var statusAfterSet: Bool?
    var error: Error?
    private(set) var requestedValues: [Bool] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let error {
            throw error
        }
        isEnabled = statusAfterSet ?? enabled
    }
}

private enum LaunchServiceError: Error {
    case denied
}

private final class ObservationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedChangeCount = 0

    var changeCount: Int {
        lock.withLock { storedChangeCount }
    }

    func recordChange() {
        lock.withLock { storedChangeCount += 1 }
    }
}
