import Foundation
import Darwin

public struct CompletionResult: Sendable {
    public let prefix: String; public let suggestion: String
    public let confidence: Float; public let isMLBased: Bool
    public init(prefix: String, suggestion: String, confidence: Float, isMLBased: Bool) {
        self.prefix = prefix; self.suggestion = suggestion; self.confidence = confidence; self.isMLBased = isMLBased
    }
}

public struct GrammarResult: Sendable {
    public let original: String; public let corrected: String
    public let suggestions: [String]; public let confidence: Float
    public init(original: String, corrected: String, suggestions: [String], confidence: Float) {
        self.original = original; self.corrected = corrected; self.suggestions = suggestions; self.confidence = confidence
    }
}

public struct CodeReshapeResult: Sendable {
    public let original: String; public let reshaped: String
    public let operation: String; public let confidence: Float
    public init(original: String, reshaped: String, operation: String, confidence: Float) {
        self.original = original; self.reshaped = reshaped; self.operation = operation; self.confidence = confidence
    }
}

public struct DownloadResult: Sendable {
    public let modelName: String; public let localPath: String
    public let sizeBytes: UInt64; public let sizeMB: Double
    public init(modelName: String, localPath: String, sizeBytes: UInt64, sizeMB: Double) {
        self.modelName = modelName; self.localPath = localPath; self.sizeBytes = sizeBytes; self.sizeMB = sizeMB
    }
}

public struct TabyrusHardwareInfo: Sendable {
    public let totalRamGB: Double; public let hasAppleSilicon: Bool
    public let cpuCount: UInt32; public let recommendedModel: String
    public init(totalRamGB: Double, hasAppleSilicon: Bool, cpuCount: UInt32, recommendedModel: String) {
        self.totalRamGB = totalRamGB; self.hasAppleSilicon = hasAppleSilicon; self.cpuCount = cpuCount; self.recommendedModel = recommendedModel
    }
}

public struct ClipboardAnalysis: Sendable {
    public let textType: String; public let appName: String
    public let summary: String; public let relevanceScore: Float
    public init(textType: String, appName: String, summary: String, relevanceScore: Float) {
        self.textType = textType; self.appName = appName; self.summary = summary; self.relevanceScore = relevanceScore
    }
}

public final class TabyrusBackend: @unchecked Sendable {
    public static let shared = TabyrusBackend()

    private let handle: UnsafeMutableRawPointer?
    private let libPath: String

    private init() {
        if let loaded = Self.loadLibrary() {
            handle = loaded.handle
            libPath = loaded.path
            print("TabyrusBackend: loaded \(loaded.path)")
        } else {
            handle = nil
            libPath = ""
            print("TabyrusBackend: dlopen failed, falling back to RTLD_DEFAULT")
        }
        callVoid("tabyrus_init")
        if handle == nil {
            let ok = sym("tabyrus_init") != nil
            print("TabyrusBackend: init via RTLD_DEFAULT: \(ok ? "OK" : "FAIL")")
        }
    }

    private static func loadLibrary() -> (handle: UnsafeMutableRawPointer, path: String)? {
        let names = ["libtabyrus_backend.dylib", "libtabyrus_backend.so"]
        let dirs = ["./target/debug", "./target/release"]
        for dir in dirs {
            for name in names {
                let path = "\(dir)/\(name)"
                if FileManager.default.fileExists(atPath: path),
                   let h = dlopen(path, RTLD_LAZY) {
                    return (h, path)
                }
            }
        }
        if let execPath = Bundle.main.executablePath {
            let execDir = (execPath as NSString).deletingLastPathComponent
            let parent = (execDir as NSString).deletingLastPathComponent
            for tryDir in [execDir, parent, (parent as NSString).deletingLastPathComponent] {
                for name in names {
                    let path = "\(tryDir)/\(name)"
                    if FileManager.default.fileExists(atPath: path),
                       let h = dlopen(path, RTLD_LAZY) {
                        return (h, path)
                    }
                }
            }
        }
        if let bundlePath = Bundle.main.path(forResource: "libtabyrus_backend", ofType: "dylib"),
           let h = dlopen(bundlePath, RTLD_LAZY) {
            return (h, bundlePath)
        }
        return nil
    }

    private func sym<T>(_ name: String) -> T? {
        if let h = handle, let s = dlsym(h, name) {
            return unsafeBitCast(s, to: T.self)
        }
        if let s = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            return unsafeBitCast(s, to: T.self)
        }
        return nil
    }

    private func callVoid(_ name: String) {
        (sym(name) as (@convention(c) () -> Void)?)?()
    }

    private func callString(_ name: String, _ arg: String) -> String? {
        guard let fn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?) = sym(name),
              let cStr = arg.cString(using: .utf8),
              let ptr = fn(cStr) else { return nil }
        defer {
            let free: (@convention(c) (UnsafeMutablePointer<CChar>) -> Void)? = sym("tabyrus_free_string")
            free?(ptr)
        }
        return String(cString: ptr)
    }

    public func getCompletion(for text: String) -> CompletionResult? {
        guard let json = callString("tabyrus_get_completion", text),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prefix = obj["prefix"] as? String,
              let suggestion = obj["suggestion"] as? String,
              let confidence = obj["confidence"] as? Double,
              let isMLBased = obj["is_ml_based"] as? Bool
        else { return nil }
        return CompletionResult(prefix: prefix, suggestion: suggestion, confidence: Float(confidence), isMLBased: isMLBased)
    }

    public func normalizeSuggestion(_ suggestion: String, input: String) -> String? {
        guard let fn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafePointer<CChar>?) = sym("tabyrus_normalize_suggestion"),
              let s = suggestion.cString(using: .utf8), let i = input.cString(using: .utf8),
              let ptr = fn(s, i) else { return nil }
        return String(cString: ptr)
    }

    public func setModel(_ name: String) {
        let fn: (@convention(c) (UnsafePointer<CChar>) -> Void)? = sym("tabyrus_set_model")
        name.withCString { fn?($0) }
    }

    public func setCodeReshapeEnabled(_ enabled: Bool) {
        (sym("tabyrus_set_code_reshape_enabled") as (@convention(c) (Bool) -> Void)?)?(enabled)
    }

    public func setGrammarEnabled(_ enabled: Bool) {
        (sym("tabyrus_set_grammar_enabled") as (@convention(c) (Bool) -> Void)?)?(enabled)
    }

    public func checkGrammar(_ text: String) -> GrammarResult? {
        guard let fn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?) = sym("tabyrus_check_grammar"),
              let c = text.cString(using: .utf8), let ptr = fn(c) else { return nil }
        defer {
            (sym("tabyrus_free_grammar_result") as (@convention(c) (UnsafeMutableRawPointer) -> Void)?)?(ptr)
        }
        struct C { var original: UnsafePointer<CChar>?; var corrected: UnsafePointer<CChar>?; var suggestions: UnsafePointer<CChar>?; var confidence: Float }
        let r = ptr.assumingMemoryBound(to: C.self).pointee
        let suggestions: [String] = r.suggestions.flatMap { ptr -> [String] in
            guard let s = String(cString: ptr).data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: s) as? [String] else { return [] }
            return parsed
        } ?? []
        return GrammarResult(original: text, corrected: r.corrected.map { String(cString: $0) } ?? text, suggestions: suggestions, confidence: r.confidence)
    }

    public func reshapeCode(_ code: String, operation: String) -> CodeReshapeResult? {
        guard let fn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?) = sym("tabyrus_reshape_code"),
              let cc = code.cString(using: .utf8), let co = operation.cString(using: .utf8), let ptr = fn(cc, co) else { return nil }
        defer {
            (sym("tabyrus_free_code_reshape_result") as (@convention(c) (UnsafeMutableRawPointer) -> Void)?)?(ptr)
        }
        struct C { var original: UnsafePointer<CChar>?; var reshaped: UnsafePointer<CChar>?; var operation: UnsafePointer<CChar>?; var confidence: Float }
        let r = ptr.assumingMemoryBound(to: C.self).pointee
        return CodeReshapeResult(original: code, reshaped: r.reshaped.map { String(cString: $0) } ?? code, operation: r.operation.map { String(cString: $0) } ?? operation, confidence: r.confidence)
    }

    public func downloadModel(_ name: String, completion: @escaping (Result<DownloadResult, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                completion(.failure(NSError(domain: "Tabyrus", code: 1, userInfo: [NSLocalizedDescriptionKey: "Library not loaded"])))
                return
            }
            guard let fn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?) = self.sym("tabyrus_download_model"),
                  let c = name.cString(using: .utf8), let ptr = fn(c) else {
                completion(.failure(NSError(domain: "Tabyrus", code: 2, userInfo: [NSLocalizedDescriptionKey: "Download failed"])))
                return
            }

            struct C { var modelName: UnsafePointer<CChar>?; var localPath: UnsafePointer<CChar>?; var success: Bool; var errorMessage: UnsafePointer<CChar>?; var sizeBytes: UInt64 }
            let r = ptr.assumingMemoryBound(to: C.self).pointee

            let success = r.success
            let path = r.localPath.map { String(cString: $0) } ?? ""
            let modelNameStr = r.modelName.map { String(cString: $0) } ?? name
            let errorMsg = r.errorMessage.map { String(cString: $0) }
            let sizeBytes = r.sizeBytes

            (self.sym("tabyrus_free_model_download_result") as (@convention(c) (UnsafeMutableRawPointer) -> Void)?)?(ptr)

            if success {
                completion(.success(DownloadResult(modelName: modelNameStr, localPath: path, sizeBytes: sizeBytes, sizeMB: Double(sizeBytes) / 1_048_576.0)))
            } else {
                completion(.failure(NSError(domain: "Tabyrus", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "Unknown error"])))
            }
        }
    }

    public func isModelDownloaded(_ name: String) -> Bool {
        guard let fn: (@convention(c) (UnsafePointer<CChar>) -> Int32) = sym("tabyrus_is_model_downloaded") else {
            fputs("[tabyrus-swift] isModelDownloaded: dlsym failed for tabyrus_is_model_downloaded\n", stderr)
            return false
        }
        let result = name.withCString { fn($0) }
        fputs("[tabyrus-swift] isModelDownloaded(\(name)) = \(result)\n", stderr)
        return result != 0
    }

    public func getModelCachePath(_ name: String) -> String? {
        guard let fn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?) = sym("tabyrus_get_model_cache_path") else { return nil }
        return name.withCString { fn($0).map { String(cString: $0) } }
    }

    public func setHFToken(_ token: String?) {
        if let token {
            (sym("tabyrus_set_hf_token") as (@convention(c) (UnsafePointer<CChar>) -> Void)?)?.self(token.cString(using: .utf8)!)
        } else {
            (sym("tabyrus_set_hf_token") as (@convention(c) (UnsafePointer<CChar>?) -> Void)?)?.self(nil)
        }
    }

    public func detectHardware() -> TabyrusHardwareInfo? {
        guard let fn: (@convention(c) () -> UnsafeMutableRawPointer?) = sym("tabyrus_detect_hardware"), let ptr = fn() else { return nil }
        defer {
            (sym("tabyrus_free_hardware_info") as (@convention(c) (UnsafeMutableRawPointer) -> Void)?)?(ptr)
        }
        struct C { var total_ram_gb: Double; var has_apple_silicon: Bool; var cpu_count: UInt32; var recommended_model: UnsafePointer<CChar>? }
        let r = ptr.assumingMemoryBound(to: C.self).pointee
        return TabyrusHardwareInfo(totalRamGB: r.total_ram_gb, hasAppleSilicon: r.has_apple_silicon, cpuCount: r.cpu_count, recommendedModel: r.recommended_model.map { String(cString: $0) } ?? "gemma-4")
    }

    public func analyzeClipboard(content: String, appName: String) -> ClipboardAnalysis? {
        guard let fn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?) = sym("tabyrus_analyze_clipboard"),
              let cc = content.cString(using: .utf8), let ca = appName.cString(using: .utf8), let ptr = fn(cc, ca) else { return nil }
        defer {
            (sym("tabyrus_free_clipboard_analysis") as (@convention(c) (UnsafeMutableRawPointer) -> Void)?)?(ptr)
        }
        struct C { var text_type: UnsafePointer<CChar>?; var app_name: UnsafePointer<CChar>?; var summary: UnsafePointer<CChar>?; var relevance_score: Float }
        let r = ptr.assumingMemoryBound(to: C.self).pointee
        return ClipboardAnalysis(textType: r.text_type.map { String(cString: $0) } ?? "unknown", appName: r.app_name.map { String(cString: $0) } ?? appName, summary: r.summary.map { String(cString: $0) } ?? "", relevanceScore: r.relevance_score)
    }
}
