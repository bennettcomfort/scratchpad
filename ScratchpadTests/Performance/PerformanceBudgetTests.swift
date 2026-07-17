import AppKit
import XCTest
@testable import Scratchpad

@MainActor
final class PerformanceBudgetTests: XCTestCase {
    func testTwoMegabyteMetricsCalculationCompletesWithin150Milliseconds() {
        XCTAssertEqual(PerformanceProbe.subsystem, "com.scratchpad.app")
        let text = String(repeating: "word ", count: 400_000)
        XCTAssertEqual(text.utf8.count, 2_000_000)

        _ = DocumentMetricsCalculator.calculate(text: text, countsWhitespace: true)

        let clock = ContinuousClock()
        var durations: [Duration] = []
        for _ in 0..<5 {
            let start = clock.now
            let metrics = DocumentMetricsCalculator.calculate(
                text: text,
                countsWhitespace: true
            )
            durations.append(start.duration(to: clock.now))
            XCTAssertEqual(metrics.estimatedTokens, 500_000)
        }

        let slowest = durations.max() ?? .zero
        XCTAssertLessThan(
            slowest,
            .milliseconds(150),
            "Slowest 2 MB metrics calculation was \(slowest)"
        )
    }

    func testRecoveryVirtualClockFiresBetweenTwoAndTwoPointFiveSeconds() async {
        let clock = PerformanceVirtualRecoveryClock()
        let repository = PerformanceSessionRepository(clock: clock)
        let document = DocumentSession(
            text: "recover me",
            hasUnsavedChanges: true,
            generation: 1
        )
        let coordinator = RecoveryCoordinator(
            repository: repository,
            clock: clock,
            documentProvider: { id in id == document.id ? document : nil }
        )

        coordinator.scheduleRecovery(for: document)
        let sleeperStarted = await waitUntil { await clock.hasSleeper }
        XCTAssertTrue(sleeperStarted)
        await clock.advance(by: .seconds(2.25))
        let recoveryWritten = await waitUntil { await repository.writeInstant != nil }
        XCTAssertTrue(recoveryWritten)

        let requestedDelay = await clock.requestedDelay
        let writeInstant = await repository.writeInstant
        XCTAssertEqual(requestedDelay, .seconds(2))
        XCTAssertGreaterThanOrEqual(writeInstant ?? .zero, .seconds(2))
        XCTAssertLessThanOrEqual(writeInstant ?? .seconds(3), .seconds(2.5))
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return await condition()
    }
}

private actor PerformanceVirtualRecoveryClock: RecoveryClock {
    private(set) var requestedDelay: Duration?
    private(set) var now: Duration = .zero
    private var sleeper: CheckedContinuation<Void, Error>?

    var hasSleeper: Bool {
        sleeper != nil
    }

    func sleep(for duration: Duration) async throws {
        requestedDelay = duration
        try await withCheckedThrowingContinuation { continuation in
            sleeper = continuation
        }
    }

    func advance(by duration: Duration) {
        now += duration
        guard let requestedDelay, now >= requestedDelay else { return }
        let pendingSleeper = sleeper
        sleeper = nil
        pendingSleeper?.resume()
    }
}

private actor PerformanceSessionRepository: SessionPersisting {
    private let clock: PerformanceVirtualRecoveryClock
    private(set) var writeInstant: Duration?

    init(clock: PerformanceVirtualRecoveryClock) {
        self.clock = clock
    }

    func loadSession() async throws -> SessionRecord? { nil }
    func writeSession(_ record: SessionRecord) async throws {}
    func loadRecovery(documentID: UUID) async throws -> RecoveryRecord? { nil }
    func loadAllRecovery() async throws -> [RecoveryRecord] { [] }

    func writeRecovery(_ record: RecoveryRecord) async throws {
        writeInstant = await clock.now
    }

    func deleteRecovery(documentID: UUID) async throws {}
}
