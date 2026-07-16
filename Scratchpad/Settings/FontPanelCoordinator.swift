import AppKit

@MainActor
protocol FontManaging: AnyObject {
    var target: AnyObject? { get set }
    var action: Selector { get set }

    func setSelectedFont(_ font: NSFont, isMultiple: Bool)
    func orderFrontFontPanel(_ sender: Any?)
    func convert(_ font: NSFont) -> NSFont
}

extension NSFontManager: FontManaging {}

@MainActor
final class FontPanelCoordinator: NSObject {
    private let settings: SettingsStore
    private let fontManager: any FontManaging
    private weak var previousTarget: AnyObject?
    private var previousAction = NSSelectorFromString("changeFont:")
    private var currentFont: NSFont
    private var ownsFontManager = false

    init(
        settings: SettingsStore,
        fontManager: any FontManaging = NSFontManager.shared
    ) {
        self.settings = settings
        self.fontManager = fontManager
        currentFont = Self.resolveFont(settings.snapshot.font)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontPanelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func open() {
        if !ownsFontManager {
            previousTarget = fontManager.target
            previousAction = fontManager.action
            ownsFontManager = true
        }
        currentFont = Self.resolveFont(settings.snapshot.font)
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))
        fontManager.setSelectedFont(currentFont, isMultiple: false)
        fontManager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        let convertedFont = fontManager.convert(currentFont)
        currentFont = convertedFont
        settings.setFont(
            FontPreference(
                postScriptName: convertedFont.fontName,
                pointSize: convertedFont.pointSize
            )
        )
    }

    func close() {
        guard ownsFontManager else { return }
        fontManager.target = previousTarget
        fontManager.action = previousAction
        previousTarget = nil
        previousAction = NSSelectorFromString("changeFont:")
        ownsFontManager = false
    }

    @objc private func fontPanelWillClose(_ notification: Notification) {
        guard notification.object is NSFontPanel else { return }
        close()
    }

    private static func resolveFont(_ preference: FontPreference) -> NSFont {
        if preference.pointSize > 0,
           let font = NSFont(name: preference.postScriptName, size: preference.pointSize) {
            return font
        }
        return NSFont(name: "SFMono-Regular", size: 15)
            ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    }
}
