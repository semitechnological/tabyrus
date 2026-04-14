//
//  OttoSettings.swift
//  Otto
//
//  Manages user settings and preferences
//

import Foundation
import OttoBackend

enum OttoModel: String, Codable, CaseIterable {
    case zeta2 = "zeta-2"
    case qwen35 = "qwen-3.5"
    case gemma4 = "gemma-4"
    
    var displayName: String {
        switch self {
        case .zeta2:
            return "Zeta-2 (Recommended)"
        case .qwen35:
            return "Qwen 3.5"
        case .gemma4:
            return "Gemma 4"
        }
    }
    
    var description: String {
        switch self {
        case .zeta2:
            return "NexVeridian/zeta-2-4bit: Code editing specialist with next-edit-prediction"
        case .qwen35:
            return "Qwen3.5-0.8B-OptiQ-4bit: General purpose language model"
        case .gemma4:
            return "mlx-community/gemma-4-e2b-it-4bit: Google's Gemma 4 instruction-tuned, multimodal (~3.6GB)"
        }
    }
    
    var modelIdentifier: String {
        switch self {
        case .zeta2:
            return "NexVeridian/zeta-2-4bit"
        case .qwen35:
            return "Qwen3.5-0.8B"
        case .gemma4:
            return "mlx-community/gemma-4-e2b-it-4bit"
        }
    }
}

struct OttoSettings: Codable {
    var selectedModel: OttoModel
    var codeReshapeEnabled: Bool
    var grammarCheckEnabled: Bool
    var codeReshapeBehavior: CodeReshapeBehavior
    var monitoringEnabled: Bool
    var clipboardMonitoringEnabled: Bool
    var screenshotMonitoringEnabled: Bool
    
    enum CodeReshapeBehavior: String, Codable, CaseIterable {
        case onDemand = "on_demand"
        case onType = "on_type"
        case onCompletion = "on_completion"
        
        var displayName: String {
            switch self {
            case .onDemand:
                return "On Demand (Ctrl+Shift+R)"
            case .onType:
                return "As You Type"
            case .onCompletion:
                return "After Tab Completion"
            }
        }
        
        var description: String {
            switch self {
            case .onDemand:
                return "Press Ctrl+Shift+R to reshape selected code"
            case .onType:
                return "Continuously suggest improvements while typing"
            case .onCompletion:
                return "Suggest refactoring after accepting a completion"
            }
        }
    }
    
    static var `default`: OttoSettings {
        OttoSettings(
            selectedModel: .zeta2,
            codeReshapeEnabled: false,
            grammarCheckEnabled: false,
            codeReshapeBehavior: .onDemand,
            monitoringEnabled: true,
            clipboardMonitoringEnabled: true,
            screenshotMonitoringEnabled: false
        )
    }
}

class OttoSettingsManager {
    static let shared = OttoSettingsManager()
    
    private let settingsKey = "OttoSettings"
    private var settings: OttoSettings
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(OttoSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
        applySettings()
    }
    
    var currentSettings: OttoSettings {
        get { settings }
        set {
            settings = newValue
            save()
            applySettings()
        }
    }
    
    func setModel(_ model: OttoModel) {
        settings.selectedModel = model
        save()
        applySettings()
    }
    
    func setCodeReshapeEnabled(_ enabled: Bool) {
        settings.codeReshapeEnabled = enabled
        save()
        applySettings()
    }
    
    func setGrammarCheckEnabled(_ enabled: Bool) {
        settings.grammarCheckEnabled = enabled
        save()
        applySettings()
    }
    
    func setCodeReshapeBehavior(_ behavior: OttoSettings.CodeReshapeBehavior) {
        settings.codeReshapeBehavior = behavior
        save()
        applySettings()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    private func applySettings() {
        let backend = OttoBackend.shared
        backend.setModel(settings.selectedModel.rawValue)
        backend.setCodeReshapeEnabled(settings.codeReshapeEnabled)
        backend.setGrammarEnabled(settings.grammarCheckEnabled)
    }
    
    func resetToDefaults() {
        settings = .default
        save()
        applySettings()
    }
}
