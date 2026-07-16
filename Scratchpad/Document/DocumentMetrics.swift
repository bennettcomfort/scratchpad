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
        var characters = 0
        var words = 0
        var isInsideWord = false

        for character in text {
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
        }

        let lines = text.unicodeScalars.reduce(into: 1) { count, scalar in
            if scalar.value == 0x0A {
                count += 1
            }
        }
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
