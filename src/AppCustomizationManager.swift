//
//  AppCustomizationManager.swift
//  Otto
//
//  Manages per-app customizations and AI-generated instructions
//

import Foundation

struct AppCustomization: Codable {
    let appName: String
    let bundleIdentifier: String
    var customInstructions: String
    var clipboardPatterns: [String]
    var interactionPatterns: [String]
    var lastUpdated: Date
    var usageCount: Int
    
    mutating func updateInstructions(_ newInstructions: String) {
        customInstructions = newInstructions
        lastUpdated = Date()
        usageCount += 1
    }
    
    func generateContextPrompt() -> String {
        var context = "App: \(appName)\n"
        context += "Instructions: \(customInstructions)\n"
        
        if !clipboardPatterns.isEmpty {
            context += "Common clipboard patterns: \(clipboardPatterns.joined(separator: ", "))\n"
        }
        
        if !interactionPatterns.isEmpty {
            context += "Common interactions: \(interactionPatterns.joined(separator: ", "))\n"
        }
        
        return context
    }
}

class AppCustomizationManager {
    private var customizations: [String: AppCustomization] = [:] // bundleIdentifier -> customization
    private let storageKey = "AppCustomizations"
    
    // AI service for generating instructions
    private var aiService: AIService?
    
    init(aiService: AIService? = nil) {
        self.aiService = aiService
        loadCustomizations()
    }
    
    // Get customization for an app
    func getCustomization(for bundleIdentifier: String, appName: String) -> AppCustomization {
        if let existing = customizations[bundleIdentifier] {
            return existing
        }
        
        // Create default customization
        let defaultCustomization = AppCustomization(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            customInstructions: generateDefaultInstructions(for: appName),
            clipboardPatterns: [],
            interactionPatterns: [],
            lastUpdated: Date(),
            usageCount: 0
        )
        
        customizations[bundleIdentifier] = defaultCustomization
        saveCustomizations()
        
        return defaultCustomization
    }
    
    // Update customization with new data
    func updateCustomization(for bundleIdentifier: String, clipboardContent: String? = nil, interaction: String? = nil) {
        guard var customization = customizations[bundleIdentifier] else { return }
        
        // Update patterns
        if let content = clipboardContent, !content.isEmpty {
            if !customization.clipboardPatterns.contains(content) {
                customization.clipboardPatterns.append(content)
                // Keep only recent patterns
                if customization.clipboardPatterns.count > 10 {
                    customization.clipboardPatterns.removeFirst()
                }
            }
        }
        
        if let interaction = interaction {
            if !customization.interactionPatterns.contains(interaction) {
                customization.interactionPatterns.append(interaction)
                if customization.interactionPatterns.count > 10 {
                    customization.interactionPatterns.removeFirst()
                }
            }
        }
        
        customizations[bundleIdentifier] = customization
        saveCustomizations()
        
        // Trigger AI instruction generation if enough data
        if customization.usageCount > 5 && aiService != nil {
            generateAIInstructions(for: bundleIdentifier)
        }
    }
    
    private func generateDefaultInstructions(for appName: String) -> String {
        // Default instructions based on app type
        let lowerName = appName.lowercased()
        
        if lowerName.contains("browser") || lowerName.contains("safari") || lowerName.contains("chrome") {
            return "This is a web browser. Provide helpful completions for URLs, search queries, and web-related text."
        } else if lowerName.contains("text") || lowerName.contains("editor") || lowerName.contains("notes") {
            return "This is a text editor. Focus on grammar, spelling, and writing assistance."
        } else if lowerName.contains("terminal") || lowerName.contains("shell") {
            return "This is a terminal/command-line application. Provide shell commands, file paths, and technical assistance."
        } else if lowerName.contains("mail") || lowerName.contains("email") {
            return "This is an email application. Help with email composition, grammar, and professional communication."
        } else if lowerName.contains("code") || lowerName.contains("xcode") || lowerName.contains("vscode") {
            return "This is a code editor. Provide programming assistance, code completion, and technical suggestions."
        } else {
            return "This is \(appName). Provide contextual assistance based on user interactions and clipboard content."
        }
    }
    
    private func generateAIInstructions(for bundleIdentifier: String) {
        guard let aiService = aiService, var customization = customizations[bundleIdentifier] else { return }
        
        let prompt = """
        Analyze this application's usage patterns and generate customized AI instructions for an autocomplete system.
        
        App: \(customization.appName)
        Bundle ID: \(customization.bundleIdentifier)
        
        Recent clipboard patterns:
        \(customization.clipboardPatterns.joined(separator: "\n"))
        
        Recent interaction patterns:
        \(customization.interactionPatterns.joined(separator: "\n"))
        
        Based on this data, generate specific instructions for how the AI should behave when providing completions in this app. Focus on the app's purpose, common workflows, and appropriate completion styles.
        """
        
        Task {
            do {
                let aiInstructions = try await aiService.generateInstructions(prompt: prompt)
                customization.updateInstructions(aiInstructions)
                self.customizations[bundleIdentifier] = customization
                self.saveCustomizations()
                print("Updated AI instructions for \(customization.appName)")
            } catch {
                print("Failed to generate AI instructions: \(error)")
            }
        }
    }
    
    // Get context for AI completion
    func getContextForApp(_ bundleIdentifier: String) -> String? {
        guard let customization = customizations[bundleIdentifier] else { return nil }
        return customization.generateContextPrompt()
    }
    
    // Storage methods
    private func saveCustomizations() {
        do {
            let data = try JSONEncoder().encode(customizations)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save customizations: \(error)")
        }
    }
    
    private func loadCustomizations() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        
        do {
            customizations = try JSONDecoder().decode([String: AppCustomization].self, from: data)
            print("Loaded \(customizations.count) app customizations")
        } catch {
            print("Failed to load customizations: \(error)")
        }
    }
    
    // Clear all customizations
    func clearAllCustomizations() {
        customizations.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("All app customizations cleared")
    }
}