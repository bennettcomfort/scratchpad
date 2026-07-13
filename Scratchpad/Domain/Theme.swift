import SwiftUI

struct EditorTheme: Sendable, Equatable, Codable {
    var name: String
    var backgroundHex: String
    var textHex: String
    var secondaryHex: String
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var leftPadding: CGFloat
    var topPadding: CGFloat

    var background: Color { Color(hex: backgroundHex) ?? .black }
    var text: Color { Color(hex: textHex) ?? .white }
    var secondary: Color { Color(hex: secondaryHex) ?? .gray }

    var nsBackground: NSColor { NSColor(background) }
    var nsText: NSColor { NSColor(text) }
    var nsSecondary: NSColor { NSColor(secondary) }
    var nsFont: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var nsHeadingFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize * 1.18, weight: .semibold)
    }

    static let scratchDark = EditorTheme(
        name: "Scratch Dark",
        backgroundHex: "#2E2E2E", textHex: "#ECECEC", secondaryHex: "#9A9A9A",
        fontSize: 22, lineHeight: 1.45, leftPadding: 60, topPadding: 42)

    static let scratchLight = EditorTheme(
        name: "Scratch Light",
        backgroundHex: "#F6F6F4", textHex: "#1E1E1E", secondaryHex: "#8C8C8C",
        fontSize: 22, lineHeight: 1.45, leftPadding: 60, topPadding: 42)

    static let system = EditorTheme(
        name: "System",
        backgroundHex: "#FFFFFF", textHex: "#000000", secondaryHex: "#888888",
        fontSize: 22, lineHeight: 1.45, leftPadding: 60, topPadding: 42)

    static let highContrast = EditorTheme(
        name: "High Contrast",
        backgroundHex: "#FFFFFF", textHex: "#000000", secondaryHex: "#4D4D4D",
        fontSize: 22, lineHeight: 1.45, leftPadding: 60, topPadding: 42)

    static let all: [EditorTheme] = [.scratchDark, .scratchLight, .system, .highContrast]
}

private extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let r = UInt8(hex[hex.index(hex.startIndex, offsetBy: 1)..<hex.index(hex.startIndex, offsetBy: 3)], radix: 16)
        let g = UInt8(hex[hex.index(hex.startIndex, offsetBy: 3)..<hex.index(hex.startIndex, offsetBy: 5)], radix: 16)
        let b = UInt8(hex[hex.index(hex.startIndex, offsetBy: 5)..<hex.index(hex.startIndex, offsetBy: 7)], radix: 16)
        guard let r, let g, let b else { return nil }
        self.init(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}
