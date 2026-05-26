import Foundation

struct SuggestionRequest {
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let stopSequences: [String]

    static func forCompletion(text: String) -> SuggestionRequest? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let words = trimmed.split(separator: " ", omittingEmptySubsequences: false)
        guard let lastWord = words.last, !lastWord.isEmpty else { return nil }
        guard lastWord.count >= 2 else { return nil }

        let recentWords = words.suffix(20).joined(separator: " ")

        return SuggestionRequest(
            prompt: recentWords,
            maxTokens: 32,
            temperature: 0.3,
            stopSequences: ["\n\n", "\n"]
        )
    }
}

enum SuggestionAvailabilityEvaluator {
    static func shouldGenerate(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let words = trimmed.split(separator: " ")
        guard let lastWord = words.last else { return false }
        return lastWord.count >= 2
    }
}
