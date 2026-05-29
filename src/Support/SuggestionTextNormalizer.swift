import Foundation

enum SuggestionTextNormalizer {
    static func normalize(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r", with: "")
        result = result.replacingOccurrences(of: "<|im_end|>", with: "")
        result = result.replacingOccurrences(of: "<|im_start|>", with: "")

        if let thinkRange = result.range(of: "<think>[\\s\\S]*?</think>", options: .regularExpression) {
            result.replaceSubrange(thinkRange, with: "")
        }
        if let openTag = result.range(of: "<think>[\\s\\S]*", options: .regularExpression) {
            result.replaceSubrange(openTag, with: "")
        }

        let stopPatterns = [
            "\n\n", "\nfn ", "\nimpl ", "\nmod ", "\nstruct ",
            "\npub ", "\ntrait ", "\nuse ", "\nlet ", "\nif ",
            "```", "<|", "```", "\n---"
        ]

        for pattern in stopPatterns {
            if let range = result.range(of: pattern) {
                result = String(result[..<range.lowerBound])
            }
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        let maxWords = 12
        let words = result.split(separator: " ")
        if words.count > maxWords {
            result = words.prefix(maxWords).joined(separator: " ")
        }

        return result
    }

    static func formatGhostText(_ suggestion: String, relativeTo prefix: String) -> String {
        return stripEchoPrefix(suggestion, precedingText: prefix)
    }

    private static func stripEchoPrefix(_ suggestion: String, precedingText: String) -> String {
        let suggestionWords = suggestion.split(whereSeparator: { $0.isWhitespace })
        guard !suggestionWords.isEmpty else { return suggestion }

        let precedingWords = precedingText.split(whereSeparator: { $0.isWhitespace })
        guard !precedingWords.isEmpty else { return suggestion }

        let maxSearchDepth = min(precedingWords.count, 15)
        var bestOverlap = 0

        for startOffset in 1...maxSearchDepth {
            let tailSlice = precedingWords.suffix(startOffset)
            let headSlice = suggestionWords.prefix(startOffset)

            guard tailSlice.count == headSlice.count else { continue }

            let matches = zip(tailSlice, headSlice).allSatisfy {
                $0.0.caseInsensitiveCompare(String($0.1)) == .orderedSame
            }

            if matches {
                bestOverlap = startOffset
            }
        }

        guard bestOverlap > 0 else { return suggestion }
        if bestOverlap >= suggestionWords.count {
            return ""
        }

        let lastEchoedWord = suggestionWords[bestOverlap - 1]
        var result = String(suggestion[lastEchoedWord.endIndex...])
        if let lastScalar = precedingText.unicodeScalars.last,
           CharacterSet.whitespaces.contains(lastScalar) {
            result = String(result.drop(while: { $0.isWhitespace }))
        }

        return result
    }
}
