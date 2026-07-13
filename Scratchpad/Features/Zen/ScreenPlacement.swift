import CoreGraphics

enum ScreenPlacement {
    static func targetFrame(mouse: CGPoint, screens: [CGRect], windowSize: CGSize) -> CGRect {
        guard let screen = screens.first(where: { $0.contains(mouse) }) ?? screens.first
        else { return CGRect(origin: .zero, size: windowSize) }
        return CGRect(x: screen.midX - windowSize.width / 2,
                      y: screen.midY - windowSize.height / 2,
                      width: windowSize.width, height: windowSize.height)
    }
}
