import Foundation

enum SuggestionTextNormalizer {
    static func normalize(_ text: String) -> String {
        var result = text

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
        let suggestionLower = suggestion.lowercased()
        let prefixLower = prefix.lowercased()

        if suggestionLower.hasPrefix(prefixLower) {
            return String(suggestion.dropFirst(prefixLower.count))
        }

        return suggestion
    }
}
