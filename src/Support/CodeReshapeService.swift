//
//  CodeReshapeService.swift
//  Tabyrus
//
//  Service for code reshaping/refactoring suggestions
//

import Foundation
import AppKit

protocol CodeReshapeServiceDelegate: AnyObject {
    func codeReshapeService(_ service: CodeReshapeService, didSuggestReshape result: CodeReshapeResult, for code: String)
    func codeReshapeService(_ service: CodeReshapeService, didFailWithError error: Error)
}

class CodeReshapeService {
    weak var delegate: CodeReshapeServiceDelegate?
    private let backend: TabyrusBackend
    private var isProcessing = false
    
    enum ReshapeOperation: String, CaseIterable {
        case refactor = "refactor"
        case simplify = "simplify"
        case optimize = "optimize"
        case format = "format"
        case extract = "extract"
        case inline = "inline"
        case rename = "rename"
        
        var displayName: String {
            switch self {
            case .refactor: return "Refactor"
            case .simplify: return "Simplify"
            case .optimize: return "Optimize"
            case .format: return "Format"
            case .extract: return "Extract"
            case .inline: return "Inline"
            case .rename: return "Rename"
            }
        }
        
        var icon: String {
            switch self {
            case .refactor: return "🔄"
            case .simplify: return "📝"
            case .optimize: return "⚡"
            case .format: return "🎨"
            case .extract: return "📦"
            case .inline: return "🔗"
            case .rename: return "✏️"
            }
        }
    }
    
    init(backend: TabyrusBackend = .shared) {
        self.backend = backend
    }
    
    func reshape(_ code: String, operation: ReshapeOperation) {
        guard !isProcessing else { return }
        isProcessing = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let result = self.backend.reshapeCode(code, operation: operation.rawValue) {
                DispatchQueue.main.async {
                    self.delegate?.codeReshapeService(self, didSuggestReshape: result, for: code)
                    self.isProcessing = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
            }
        }
    }
    
    func reshapeOnDemand(_ code: String) {
        reshape(code, operation: .refactor)
    }
    
    func reshapeWithSimplify(_ code: String) {
        reshape(code, operation: .simplify)
    }
    
    func reshapeWithOptimize(_ code: String) {
        reshape(code, operation: .optimize)
    }
    
    func applyReshape(_ result: CodeReshapeResult) -> Bool {
        return injectText(result.reshaped)
    }
    
    private func injectText(_ text: String) -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else {
            return false
        }
        
        let textValue = text as CFString
        let insertResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, textValue)
        
        return insertResult == .success
    }
}
