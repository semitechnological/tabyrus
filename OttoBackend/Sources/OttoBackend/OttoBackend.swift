//
//  OttoBackend.swift
//  OttoBackend
//
//  Swift wrapper for the Rust Otto backend using direct C FFI
//

import Foundation

public struct CompletionResult {
    public let prefix: String
    public let suggestion: String
    public let confidence: Float
    public let isMLBased: Bool

    public init(prefix: String, suggestion: String, confidence: Float, isMLBased: Bool) {
        self.prefix = prefix
        self.suggestion = suggestion
        self.confidence = confidence
        self.isMLBased = isMLBased
    }
}

public struct GrammarResult {
    public let original: String
    public let corrected: String
    public let suggestions: [String]
    public let confidence: Float

    public init(original: String, corrected: String, suggestions: [String], confidence: Float) {
        self.original = original
        self.corrected = corrected
        self.suggestions = suggestions
        self.confidence = confidence
    }
}

public struct CodeReshapeResult {
    public let original: String
    public let reshaped: String
    public let operation: String
    public let confidence: Float

    public init(original: String, reshaped: String, operation: String, confidence: Float) {
        self.original = original
        self.reshaped = reshaped
        self.operation = operation
        self.confidence = confidence
    }
}

public class OttoBackend {
    public static let shared = OttoBackend()
    
    private var rustLibraryHandle: UnsafeMutableRawPointer?

    public init() {
        loadRustLibrary()
        initializeBackend()
    }

    deinit {
        // Library will be unloaded automatically
    }

    private func loadRustLibrary() {
        let possiblePaths = [
            "./target/debug/libotto_backend.dylib",
            "./target/release/libotto_backend.dylib",
            Bundle.main.path(forResource: "libotto_backend", ofType: "dylib"),
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                rustLibraryHandle = dlopen(path, RTLD_LAZY)
                if rustLibraryHandle != nil {
                    print("Successfully loaded Rust library from: \(path)")
                    return
                }
            }
        }

        if rustLibraryHandle == nil {
            print("Using Swift fallback: Rust library not loaded")
        }
    }

    private func initializeBackend() {
        guard let handle = rustLibraryHandle else {
            print("Cannot initialize: Rust library not loaded")
            return
        }

        let symbolName = "otto_initialize_completions"
        guard let symbol = dlsym(handle, symbolName) else {
            print("Cannot find symbol: \(symbolName)")
            return
        }

        typealias InitFunction = @convention(c) () -> Void
        let initFunc = unsafeBitCast(symbol, to: InitFunction.self)
        initFunc()
        print("Rust backend initialized successfully")
    }

    public func getCompletion(for text: String) -> CompletionResult? {
        guard let handle = rustLibraryHandle else {
            return getSwiftFallbackCompletion(for: text)
        }

        let cString = text.cString(using: .utf8)!

        let completionSymbolName = "otto_get_completion"
        guard let completionSymbol = dlsym(handle, completionSymbolName) else {
            print("Cannot find symbol: \(completionSymbolName)")
            return getSwiftFallbackCompletion(for: text)
        }
        typealias CompletionFunction = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>
        let completionFunc = unsafeBitCast(completionSymbol, to: CompletionFunction.self)
        let resultPtr = completionFunc(cString)

        if resultPtr == UnsafeMutablePointer<CChar>(bitPattern: 0) {
            return getSwiftFallbackCompletion(for: text)
        }

        let resultString = String(cString: resultPtr)

        let freeSymbolName = "otto_free_string"
        if let freeSymbol = dlsym(handle, freeSymbolName) {
            typealias FreeFunction = @convention(c) (UnsafeMutablePointer<CChar>) -> Void
            let freeFunc = unsafeBitCast(freeSymbol, to: FreeFunction.self)
            freeFunc(resultPtr)
        }

        if let data = resultString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let prefix = json["prefix"] as? String,
           let suggestion = json["suggestion"] as? String,
           let confidence = json["confidence"] as? Double,
           let isMLBased = json["is_ml_based"] as? Bool {

            return CompletionResult(
                prefix: prefix,
                suggestion: suggestion,
                confidence: Float(confidence),
                isMLBased: isMLBased
            )
        }

        return getSwiftFallbackCompletion(for: text)
    }
    
    public func setModel(_ modelName: String) {
        guard let handle = rustLibraryHandle else {
            print("Cannot set model: Rust library not loaded")
            return
        }
        
        let symbolName = "otto_set_model"
        guard let symbol = dlsym(handle, symbolName) else {
            print("Cannot find symbol: \(symbolName)")
            return
        }
        
        let cString = modelName.cString(using: .utf8)!
        typealias SetModelFunction = @convention(c) (UnsafePointer<CChar>) -> Void
        let funcPtr = unsafeBitCast(symbol, to: SetModelFunction.self)
        funcPtr(cString)
    }
    
    public func setCodeReshapeEnabled(_ enabled: Bool) {
        guard let handle = rustLibraryHandle else {
            print("Cannot set code reshape: Rust library not loaded")
            return
        }
        
        let symbolName = "otto_set_code_reshape_enabled"
        guard let symbol = dlsym(handle, symbolName) else {
            print("Cannot find symbol: \(symbolName)")
            return
        }
        
        typealias SetBoolFunction = @convention(c) (Bool) -> Void
        let funcPtr = unsafeBitCast(symbol, to: SetBoolFunction.self)
        funcPtr(enabled)
    }
    
    public func setGrammarEnabled(_ enabled: Bool) {
        guard let handle = rustLibraryHandle else {
            print("Cannot set grammar: Rust library not loaded")
            return
        }
        
        let symbolName = "otto_set_grammar_enabled"
        guard let symbol = dlsym(handle, symbolName) else {
            print("Cannot find symbol: \(symbolName)")
            return
        }
        
        typealias SetBoolFunction = @convention(c) (Bool) -> Void
        let funcPtr = unsafeBitCast(symbol, to: SetBoolFunction.self)
        funcPtr(enabled)
    }
    
    public func checkGrammar(_ text: String) -> GrammarResult? {
        guard let handle = rustLibraryHandle else {
            return getSwiftFallbackGrammar(for: text)
        }
        
        let symbolName = "otto_check_grammar"
        guard let symbol = dlsym(handle, symbolName) else {
            print("Cannot find symbol: \(symbolName)")
            return getSwiftFallbackGrammar(for: text)
        }
        
        let cString = text.cString(using: .utf8)!
        typealias GrammarFunction = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let funcPtr = unsafeBitCast(symbol, to: GrammarFunction.self)
        
        guard let resultPtr = funcPtr(cString) else {
            return nil
        }
        
        defer {
            let freeSymbolName = "otto_free_grammar_result"
            if let freeSymbol = dlsym(handle, freeSymbolName) {
                typealias FreeFunction = @convention(c) (UnsafeMutableRawPointer) -> Void
                let freeFunc = unsafeBitCast(freeSymbol, to: FreeFunction.self)
                freeFunc(resultPtr)
            }
        }
        
        struct CGrammarResult {
            var original: UnsafePointer<CChar>?
            var corrected: UnsafePointer<CChar>?
            var suggestions: UnsafePointer<CChar>?
            var confidence: Float
        }
        
        let result = resultPtr.assumingMemoryBound(to: CGrammarResult.self).pointee
        
        let original = result.original.map { String(cString: $0) } ?? text
        let corrected = result.corrected.map { String(cString: $0) } ?? text
        
        var suggestions: [String] = []
        if let suggestionsPtr = result.suggestions,
           let suggestionsStr = String(cString: suggestionsPtr).data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: suggestionsStr) as? [String] {
            suggestions = parsed
        }
        
        return GrammarResult(
            original: original,
            corrected: corrected,
            suggestions: suggestions,
            confidence: result.confidence
        )
    }
    
    public func reshapeCode(_ code: String, operation: String) -> CodeReshapeResult? {
        guard let handle = rustLibraryHandle else {
            return getSwiftFallbackCodeReshape(for: code, operation: operation)
        }
        
        let symbolName = "otto_reshape_code"
        guard let symbol = dlsym(handle, symbolName) else {
            print("Cannot find symbol: \(symbolName)")
            return getSwiftFallbackCodeReshape(for: code, operation: operation)
        }
        
        let codeCString = code.cString(using: .utf8)!
        let opCString = operation.cString(using: .utf8)!
        
        typealias ReshapeFunction = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
        let funcPtr = unsafeBitCast(symbol, to: ReshapeFunction.self)
        
        guard let resultPtr = funcPtr(codeCString, opCString) else {
            return nil
        }
        
        defer {
            let freeSymbolName = "otto_free_code_reshape_result"
            if let freeSymbol = dlsym(handle, freeSymbolName) {
                typealias FreeFunction = @convention(c) (UnsafeMutableRawPointer) -> Void
                let freeFunc = unsafeBitCast(freeSymbol, to: FreeFunction.self)
                freeFunc(resultPtr)
            }
        }
        
        struct CCodeReshapeResult {
            var original: UnsafePointer<CChar>?
            var reshaped: UnsafePointer<CChar>?
            var operation: UnsafePointer<CChar>?
            var confidence: Float
        }
        
        let result = resultPtr.assumingMemoryBound(to: CCodeReshapeResult.self).pointee
        
        let reshaped = result.reshaped.map { String(cString: $0) } ?? code
        let op = result.operation.map { String(cString: $0) } ?? operation
        
        return CodeReshapeResult(
            original: code,
            reshaped: reshaped,
            operation: op,
            confidence: result.confidence
        )
    }

    private func getSwiftFallbackCompletion(for text: String) -> CompletionResult? {
        guard !text.isEmpty else { return nil }

        let words = text.split(separator: " ")
        guard let lastWord = words.last, !lastWord.isEmpty else { return nil }

        let prefix = String(lastWord).lowercased()

        let completions: [String: [String]] = [
            "fn": ["fn ", "fn main", "fn new"],
            "im": ["impl ", "import ", "immutable"],
            "mu": ["mut ", "mutate ", "mutable"],
            "le": ["let ", "len(", "length"],
            "su": ["struct ", "sum(", "super "],
            "co": ["const ", "continue", "count"],
            "us": ["use ", "unsafe ", "user"],
            "pa": ["pub ", "param", "parse"],
            "tr": ["trait ", "try", "true", "type"],
            "mo": ["mod ", "move", "module"],
            "ma": ["match ", "macro", "main"],
            "in": ["in ", "into ", "index", "init"],
            "if": ["if ", "impl "],
            "el": ["else", "elif ", "element"],
            "wh": ["while ", "where", "with"],
            "re": ["ref ", "return ", "result"],
            "as": ["async ", "assert", "as "],
            "aw": ["await ", "aware"],
            "the": ["then", "there", "these", "they"],
            "an": ["and", "any", "are", "as", "at"],
            "fo": ["for", "from", "of", "on", "out"],
            "ar": ["are", "and", "art", "as", "at"],
            "bu": ["but", "by", "be", "bus", "but"],
            "no": ["not", "now", "no", "nor", "new"],
            "yo": ["you", "your", "yours", "young"],
            "al": ["all", "also", "and", "as", "at"],
            "ca": ["can", "cat", "car", "case", "call"],
            "he": ["her", "he", "here", "help", "his"]
        ]

        if let candidates = completions[prefix], let best = candidates.first {
            if best.lowercased().hasPrefix(prefix) {
                let suggestion = String(best.dropFirst(prefix.count))
                return CompletionResult(
                    prefix: prefix,
                    suggestion: suggestion,
                    confidence: 0.8,
                    isMLBased: false
                )
            }
        }

        return nil
    }
    
    private func getSwiftFallbackGrammar(for text: String) -> GrammarResult? {
        var suggestions: [String] = []
        var corrected = text
        
        let grammarFixes: [(String, String, String)] = [
            ("dont", "don't", "Contract with apostrophe"),
            ("cant", "can't", "Contract with apostrophe"),
            ("wont", "won't", "Contract with apostrophe"),
            ("im ", "I'm ", "Contract with apostrophe"),
            ("your ", "you're ", "Your vs you're"),
            ("there ", "they're ", "Their vs they're"),
            ("loose", "lose", "Lose vs loose"),
            ("alot", "a lot", "Two words"),
            ("teh", "the", "Spelling")
        ]
        
        for (wrong, correct, reason) in grammarFixes {
            if corrected.lowercased().contains(wrong) {
                corrected = corrected.replacingOccurrences(of: wrong, with: correct, options: .caseInsensitive)
                suggestions.append("'\(wrong)' -> '\(correct)': \(reason)")
            }
        }
        
        if suggestions.isEmpty {
            return nil
        }
        
        return GrammarResult(
            original: text,
            corrected: corrected,
            suggestions: suggestions,
            confidence: 0.75
        )
    }
    
    private func getSwiftFallbackCodeReshape(for code: String, operation: String) -> CodeReshapeResult? {
        var reshaped = code
        
        switch operation {
        case "refactor":
            if code.contains("if x == true") {
                reshaped = code.replacingOccurrences(of: "if x == true", with: "if x")
            }
        case "simplify":
            if code.contains(".map(|x| x.clone())") {
                reshaped = code.replacingOccurrences(of: ".map(|x| x.clone())", with: ".cloned()")
            }
        default:
            break
        }
        
        if reshaped == code {
            return nil
        }
        
        return CodeReshapeResult(
            original: code,
            reshaped: reshaped,
            operation: operation,
            confidence: 0.7
        )
    }
}
