import Foundation

enum SuggestionEngine {
    case dictionary
    case mlBased
}

@MainActor
final class TabyrusSuggestionEngine {
    private let backend: TabyrusBackend

    init(backend: TabyrusBackend) {
        self.backend = backend
    }

    func generate(for text: String, context: String? = nil) -> TabyrusSuggestion? {
        guard !text.isEmpty else { return nil }

        if let result = backend.getCompletion(for: text) {
            return TabyrusSuggestion(
                text: result.suggestion,
                confidence: Double(result.confidence),
                engine: result.isMLBased ? .mlBased : .dictionary
            )
        }

        return nil
    }

    func generateFormatted(for text: String) -> String? {
        guard let suggestion = generate(for: text) else { return nil }

        let words = text.split(separator: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else { return nil }

        let prefix = String(lastWord).lowercased()
        let suggestionLower = suggestion.text.lowercased()

        if suggestionLower.hasPrefix(prefix) {
            return String(suggestion.text.dropFirst(prefix.count))
        }

        return suggestion.text
    }

    func generateGrammarCheck(_ text: String) -> GrammarResult? {
        return backend.checkGrammar(text)
    }

    func generateCodeReshape(_ code: String, operation: String) -> CodeReshapeResult? {
        return backend.reshapeCode(code, operation: operation)
    }
}

struct TabyrusSuggestion {
    let text: String
    let confidence: Double
    let engine: SuggestionEngine
}
