import Foundation

struct DocumentMetrics: Equatable, Sendable {
    let characters: Int
    let words: Int
    let lines: Int
    let estimatedTokens: Int
    let isEstimate: Bool

    static let empty = DocumentMetrics(
        characters: 0,
        words: 0,
        lines: 1,
        estimatedTokens: 0,
        isEstimate: true
    )
}

enum DocumentMetricsCalculator {
    static func calculate(text: String, countsWhitespace: Bool) -> DocumentMetrics {
        calculate(
            text: text,
            countsWhitespace: countsWhitespace,
            isCancelled: { false }
        ) ?? .empty
    }

    static func calculateUnlessCancelled(
        text: String,
        countsWhitespace: Bool
    ) -> DocumentMetrics? {
        calculate(
            text: text,
            countsWhitespace: countsWhitespace,
            isCancelled: { Task.isCancelled }
        )
    }

    private static func calculate(
        text: String,
        countsWhitespace: Bool,
        isCancelled: () -> Bool
    ) -> DocumentMetrics? {
        var characters = 0
        var words = 0
        var lines = 1
        var isInsideWord = false

        for character in text {
            if isCancelled() { return nil }
            let isWhitespace = character.unicodeScalars.allSatisfy {
                $0.properties.isWhitespace
            }
            if countsWhitespace || !isWhitespace {
                characters += 1
            }
            if isWhitespace {
                isInsideWord = false
            } else if !isInsideWord {
                words += 1
                isInsideWord = true
            }
            for scalar in character.unicodeScalars where scalar.value == 0x0A {
                lines += 1
            }
        }

        if isCancelled() { return nil }
        let byteCount = text.utf8.count
        let estimatedTokens = byteCount == 0
            ? 0
            : byteCount / 4 + (byteCount % 4 == 0 ? 0 : 1)

        return DocumentMetrics(
            characters: characters,
            words: words,
            lines: lines,
            estimatedTokens: estimatedTokens,
            isEstimate: true
        )
    }
}
