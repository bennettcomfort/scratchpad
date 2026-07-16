import Foundation
import XCTest
@testable import Scratchpad

@MainActor
final class MetricsCoordinatorTests: XCTestCase {
    func testCancelledScheduledWorkEndsPromptlyAndReleasesCaptures() async {
        let workEnded = expectation(description: "cancelled work ended")
        let coordinator = MetricsCoordinator(
            delay: .seconds(60),
            calculationDidStart: {},
            workDidEnd: { workEnded.fulfill() }
        )
        var probe: MetricsLifetimeProbe? = MetricsLifetimeProbe()
        weak let weakProbe = probe
        let delivery = MetricsDeliveryRecorder()

        coordinator.schedule(
            documentID: UUID(),
            generation: 0,
            text: String(repeating: "obsolete", count: 100_000),
            countsWhitespace: false,
            deliver: { [capturedProbe = probe] _, _, _ in
                _ = capturedProbe
                delivery.record()
            }
        )
        probe = nil
        XCTAssertNotNil(weakProbe)

        coordinator.cancel()

        await fulfillment(of: [workEnded], timeout: 1)
        await waitUntil { weakProbe == nil }
        XCTAssertNil(weakProbe)
        XCTAssertEqual(delivery.count, 0)
    }

    func testSupersededScheduledWorkCannotDeliver() async {
        let workEnded = expectation(description: "both scheduled tasks ended")
        workEnded.expectedFulfillmentCount = 2
        let delivery = MetricsDeliveryRecorder()
        let coordinator = MetricsCoordinator(
            delay: .milliseconds(1),
            calculationDidStart: {},
            workDidEnd: { workEnded.fulfill() }
        )

        coordinator.schedule(
            documentID: UUID(),
            generation: 1,
            text: "obsolete",
            countsWhitespace: false,
            deliver: { _, generation, _ in delivery.record(generation: generation) }
        )
        coordinator.schedule(
            documentID: UUID(),
            generation: 2,
            text: "current",
            countsWhitespace: false,
            deliver: { _, generation, _ in delivery.record(generation: generation) }
        )

        await fulfillment(of: [workEnded], timeout: 1)
        XCTAssertEqual(delivery.generations, [2])
    }

    func testCancellingRunningCalculationEndsWithoutDelivery() async {
        let calculationStarted = expectation(description: "calculation started")
        let workEnded = expectation(description: "running calculation ended")
        let delivery = MetricsDeliveryRecorder()
        let coordinator = MetricsCoordinator(
            delay: .zero,
            calculationDidStart: { calculationStarted.fulfill() },
            workDidEnd: { workEnded.fulfill() }
        )

        coordinator.schedule(
            documentID: UUID(),
            generation: 1,
            text: String(repeating: "word ", count: 500_000),
            countsWhitespace: false,
            deliver: { _, _, _ in delivery.record() }
        )
        await fulfillment(of: [calculationStarted], timeout: 1)

        coordinator.cancel()

        await fulfillment(of: [workEnded], timeout: 1)
        XCTAssertEqual(delivery.count, 0)
    }

    func testInjectedSettingsDriveInitialWhitespaceMetrics() async throws {
        let (settings, defaults, suiteName) = try makeSettings(countsWhitespace: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = ApplicationModel(
            document: DocumentSession(text: "a b"),
            settings: settings,
            metricsCoordinator: MetricsCoordinator(delay: .zero)
        )

        await waitUntil { model.metrics.characters == 3 }

        XCTAssertTrue(model.settings === settings)
        XCTAssertEqual(model.metrics.words, 2)
    }

    func testLiveModelUsesInjectedSettingsStore() throws {
        let (settings, defaults, suiteName) = try makeSettings(countsWhitespace: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = ApplicationModel.live(settings: settings)

        XCTAssertTrue(model.settings === settings)
    }

    func testWhitespaceSettingReschedulesMetricsWithoutMutatingDocument() async throws {
        let (settings, defaults, suiteName) = try makeSettings(countsWhitespace: false)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let document = DocumentSession(
            text: "a b",
            selection: TextSelection(location: 1, length: 1)
        )
        let model = ApplicationModel(
            document: document,
            settings: settings,
            metricsCoordinator: MetricsCoordinator(delay: .zero)
        )
        let editorCoordinator = EditorCoordinator(document: document, onEdit: { _ in })
        let scrollView = EditorHost.makeScrollView(
            document: document,
            coordinator: editorCoordinator
        )
        let textView = try XCTUnwrap(scrollView.documentView as? ScratchTextView)
        await waitUntil { model.metrics.characters == 2 }
        let generation = document.generation
        let selection = document.selection
        let canUndo = textView.undoManager?.canUndo

        settings.setCountsWhitespace(true)
        await waitUntil { model.metrics.characters == 3 }

        XCTAssertEqual(document.storage.string, "a b")
        XCTAssertEqual(document.generation, generation)
        XCTAssertEqual(document.selection, selection)
        XCTAssertEqual(textView.undoManager?.canUndo, canUndo)
        XCTAssertEqual(model.metrics.words, 2)
        XCTAssertEqual(model.metrics.lines, 1)
        XCTAssertEqual(model.metrics.estimatedTokens, 1)
    }

    func testCoordinatorDiscardsDifferentIdentityOrGenerationResult() async {
        let document = DocumentSession(text: "current", generation: 2)
        let modelMetricsCoordinator = MetricsCoordinator(delay: .seconds(60))
        let model = ApplicationModel(
            document: document,
            metricsCoordinator: modelMetricsCoordinator
        )
        defer { modelMetricsCoordinator.cancel() }
        let wrongIdentityProcessed = expectation(description: "wrong identity processed")
        let wrongGenerationProcessed = expectation(description: "wrong generation processed")
        let acceptedExpectation = expectation(description: "exact result accepted")
        let coordinator = MetricsCoordinator(delay: .milliseconds(1))

        coordinator.schedule(
            documentID: UUID(),
            generation: 2,
            text: "wrong identity",
            countsWhitespace: false,
            deliver: { resultDocumentID, resultGeneration, metrics in
                model.receiveMetrics(
                    documentID: resultDocumentID,
                    generation: resultGeneration,
                    metrics: metrics
                )
                wrongIdentityProcessed.fulfill()
            }
        )
        await fulfillment(of: [wrongIdentityProcessed], timeout: 1)
        XCTAssertEqual(model.metrics, .empty)
        coordinator.schedule(
            documentID: document.id,
            generation: 1,
            text: "wrong generation",
            countsWhitespace: false,
            deliver: { resultDocumentID, resultGeneration, metrics in
                model.receiveMetrics(
                    documentID: resultDocumentID,
                    generation: resultGeneration,
                    metrics: metrics
                )
                wrongGenerationProcessed.fulfill()
            }
        )
        await fulfillment(of: [wrongGenerationProcessed], timeout: 1)
        XCTAssertEqual(model.metrics, .empty)
        coordinator.schedule(
            documentID: document.id,
            generation: 2,
            text: "accepted",
            countsWhitespace: false,
            deliver: { resultDocumentID, resultGeneration, metrics in
                model.receiveMetrics(
                    documentID: resultDocumentID,
                    generation: resultGeneration,
                    metrics: metrics
                )
                acceptedExpectation.fulfill()
            }
        )

        await fulfillment(of: [acceptedExpectation], timeout: 1)
        XCTAssertEqual(model.metrics.words, 1)
        XCTAssertEqual(model.metrics.characters, 8)
        coordinator.cancel()
    }

    private func makeSettings(
        countsWhitespace: Bool
    ) throws -> (SettingsStore, UserDefaults, String) {
        let suiteName = "MetricsCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let settings = SettingsStore(
            defaults: defaults,
            launchService: MetricsLaunchServiceFake()
        )
        settings.setCountsWhitespace(countsWhitespace)
        return (settings, defaults, suiteName)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied")
    }
}

@MainActor
private final class MetricsDeliveryRecorder {
    private(set) var generations: [Int] = []
    var count: Int { generations.count }

    func record(generation: Int = 0) {
        generations.append(generation)
    }
}

@MainActor
private final class MetricsLifetimeProbe {}

@MainActor
private final class MetricsLaunchServiceFake: LaunchAtLoginServicing {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
