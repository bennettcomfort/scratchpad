import XCTest
@testable import Scratchpad

@MainActor
final class DebouncerTests: XCTestCase {
    func testCoalescesRapidCalls() async throws {
        let d = Debouncer(delay: .milliseconds(50))
        var fired: [Int] = []
        d.schedule { fired.append(1) }
        d.schedule { fired.append(2) }
        d.schedule { fired.append(3) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fired, [3])
    }
}
