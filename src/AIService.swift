//
//  AIService.swift
//  Otto
//
//  AI service implementations for completion and instruction generation
//

import Foundation
import OttoBackend

// Protocol for AI services
protocol AIService {
    func generateInstructions(prompt: String) async throws -> String
    func generateCompletion(text: String, context: String?) async throws -> String?
}

// Apple's FoundationModels service (when available)
class AppleAIService: AIService {
    private let hardwareInfo: HardwareInfo
    
    init(hardwareInfo: HardwareInfo) {
        self.hardwareInfo = hardwareInfo
    }
    
    func generateInstructions(prompt: String) async throws -> String {
        // Use rusty_foundationmodels when available
        // For now, return a fallback response
        return "Generated instructions based on app usage patterns: \(prompt.prefix(100))"
    }
    
    func generateCompletion(text: String, context: String?) async throws -> String? {
        // Use Apple's AI for completions
        // This would integrate with rusty_foundationmodels
        return nil // Fallback to other services
    }
    
    func isAvailable() -> Bool {
        // Check if Apple's AI is available on this hardware
        return hardwareInfo.hasAppleSilicon && hardwareInfo.ramGB >= 8.0
    }
}

// Fallback dictionary-based service
class DictionaryAIService: AIService {
    func generateInstructions(prompt: String) async throws -> String {
        // Simple rule-based instruction generation
        let lowerPrompt = prompt.lowercased()
        
        if lowerPrompt.contains("browser") || lowerPrompt.contains("web") {
            return "Provide web-related completions: URLs, search terms, and navigation assistance."
        } else if lowerPrompt.contains("code") || lowerPrompt.contains("programming") {
            return "Provide programming assistance: code completion, syntax help, and technical suggestions."
        } else if lowerPrompt.contains("text") || lowerPrompt.contains("writing") {
            return "Provide writing assistance: grammar, spelling, and style suggestions."
        } else {
            return "Provide contextual assistance based on user patterns and clipboard content."
        }
    }
    
    func generateCompletion(text: String, context: String?) async throws -> String? {
        // Use existing dictionary logic from OttoBackend
        let backend = OttoBackend.shared
        return backend.getCompletion(for: text)?.suggestion
    }
}

// Combined AI service that tries multiple backends
class CombinedAIService: AIService {
    private let appleService: AppleAIService
    private let dictionaryService: DictionaryAIService
    
    init(hardwareInfo: HardwareInfo) {
        self.appleService = AppleAIService(hardwareInfo: hardwareInfo)
        self.dictionaryService = DictionaryAIService()
    }
    
    func generateInstructions(prompt: String) async throws -> String {
        if appleService.isAvailable() {
            do {
                return try await appleService.generateInstructions(prompt: prompt)
            } catch {
                print("Apple AI failed, falling back to dictionary: \(error)")
            }
        }
        
        return try await dictionaryService.generateInstructions(prompt: prompt)
    }
    
    func generateCompletion(text: String, context: String?) async throws -> String? {
        if appleService.isAvailable() {
            if let result = try await appleService.generateCompletion(text: text, context: context) {
                return result
            }
        }
        
        return try await dictionaryService.generateCompletion(text: text, context: context)
    }
}