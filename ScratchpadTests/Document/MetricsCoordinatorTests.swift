import Foundation
import XCTest
@testable import Scratchpad

@MainActor
final class MetricsCoordinatorTests: XCTestCase {
    func testCoordinatorDiscardsDifferentIdentityOrGenerationResult() async {
        let document = DocumentSession(text: "current", generation: 2)
        let model = ApplicationModel(document: document)
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
}
