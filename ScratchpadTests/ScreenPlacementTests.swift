import XCTest
@testable import Scratchpad

final class ScreenPlacementTests: XCTestCase {
    let screenA = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let screenB = CGRect(x: 1600, y: 0, width: 1200, height: 800)

    func testCentersOnScreenContainingMouse() {
        let frame = ScreenPlacement.targetFrame(
            mouse: CGPoint(x: 2000, y: 300),
            screens: [screenA, screenB],
            windowSize: CGSize(width: 640, height: 400))
        XCTAssertEqual(frame.midX, screenB.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, screenB.midY, accuracy: 0.5)
        XCTAssertEqual(frame.size, CGSize(width: 640, height: 400))
    }

    func testFallsBackToFirstScreenWhenMouseOutsideAll() {
        let frame = ScreenPlacement.targetFrame(
            mouse: CGPoint(x: -5000, y: -5000),
            screens: [screenA, screenB],
            windowSize: CGSize(width: 640, height: 400))
        XCTAssertEqual(frame.midX, screenA.midX, accuracy: 0.5)
    }
}
