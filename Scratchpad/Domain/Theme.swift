import SwiftUI

struct EditorTheme: Sendable, Equatable {
    var name: String
    var background: Color
    var text: Color
    var secondary: Color
    var font: Font
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var leftPadding: CGFloat
    var rightPadding: CGFloat
    var topPadding: CGFloat
    var titleFont: Font
    var statusFont: Font
    var headingScale: CGFloat

    static let scratchDark = EditorTheme(
        name: "Scratch Dark",
        background: Color(red: 46/255, green: 46/255, blue: 46/255),
        text: Color(red: 236/255, green: 236/255, blue: 236/255),
        secondary: Color(red: 154/255, green: 154/255, blue: 154/255),
        font: .system(size: 22, design: .monospaced),
        fontSize: 22,
        lineHeight: 1.45,
        leftPadding: 60,
        rightPadding: 30,
        topPadding: 42,
        titleFont: .system(size: 17, weight: .semibold),
        statusFont: .system(size: 13),
        headingScale: 1.18
    )

    static let scratchLight = EditorTheme(
        name: "Scratch Light",
        background: Color(red: 246/255, green: 246/255, blue: 244/255),
        text: Color(red: 30/255, green: 30/255, blue: 30/255),
        secondary: Color(red: 140/255, green: 140/255, blue: 140/255),
        font: .system(size: 22, design: .monospaced),
        fontSize: 22,
        lineHeight: 1.45,
        leftPadding: 60,
        rightPadding: 30,
        topPadding: 42,
        titleFont: .system(size: 17, weight: .semibold),
        statusFont: .system(size: 13),
        headingScale: 1.18
    )

    static let system = EditorTheme(
        name: "System",
        background: Color(nsColor: .textBackgroundColor),
        text: Color(nsColor: .textColor),
        secondary: Color(nsColor: .secondaryLabelColor),
        font: .system(size: 22, design: .monospaced),
        fontSize: 22,
        lineHeight: 1.45,
        leftPadding: 60,
        rightPadding: 30,
        topPadding: 42,
        titleFont: .system(size: 17, weight: .semibold),
        statusFont: .system(size: 13),
        headingScale: 1.18
    )

    static let highContrast = EditorTheme(
        name: "High Contrast",
        background: .white,
        text: .black,
        secondary: Color(white: 0.3),
        font: .system(size: 22, design: .monospaced),
        fontSize: 22,
        lineHeight: 1.45,
        leftPadding: 60,
        rightPadding: 30,
        topPadding: 42,
        titleFont: .system(size: 17, weight: .semibold),
        statusFont: .system(size: 13),
        headingScale: 1.18
    )
}
