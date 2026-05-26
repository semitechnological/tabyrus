//
//  GrammarWidget.swift
//  Tabyrus
//
//  Floating widget for grammar checking and sentence rewording
//

import Cocoa
import AppKit

protocol GrammarWidgetDelegate: AnyObject {
    func grammarWidget(_ widget: GrammarWidget, didCorrect text: String, suggestions: [String])
    func grammarWidgetDidDismiss(_ widget: GrammarWidget)
}

class GrammarWidget: NSWindow {
    weak var grammarDelegate: GrammarWidgetDelegate?
    
    private var suggestionLabel: NSTextField!
    private var originalLabel: NSTextField!
    private var suggestionsStackView: NSStackView!
    private var applyButton: NSButton!
    private var dismissButton: NSButton!
    private var rewordButton: NSButton!
    
    private var currentResult: GrammarResult?
    private let backend: TabyrusBackend
    
    init(backend: TabyrusBackend = .shared) {
        self.backend = backend
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 120),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        setupWindow()
        setupUI()
    }
    
    private func setupWindow() {
        title = "Grammar Check"
        level = .floating
        isOpaque = false
        backgroundColor = NSColor.windowBackgroundColor
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        minSize = NSSize(width: 300, height: 100)
        maxSize = NSSize(width: 500, height: 300)
    }
    
    private func setupUI() {
        guard let contentView = contentView else { return }
        
        let containerView = NSView(frame: contentView.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.addSubview(containerView)
        
        originalLabel = NSTextField(labelWithString: "")
        originalLabel.font = NSFont.systemFont(ofSize: 11)
        originalLabel.textColor = NSColor.secondaryLabelColor
        originalLabel.lineBreakMode = .byTruncatingTail
        originalLabel.maximumNumberOfLines = 2
        containerView.addSubview(originalLabel)
        
        suggestionLabel = NSTextField(labelWithString: "")
        suggestionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        suggestionLabel.textColor = NSColor.labelColor
        suggestionLabel.lineBreakMode = .byWordWrapping
        suggestionLabel.maximumNumberOfLines = 3
        containerView.addSubview(suggestionLabel)
        
        suggestionsStackView = NSStackView()
        suggestionsStackView.orientation = .vertical
        suggestionsStackView.alignment = .leading
        suggestionsStackView.spacing = 4
        suggestionsStackView.distribution = .fill
        containerView.addSubview(suggestionsStackView)
        
        let buttonStackView = NSStackView()
        buttonStackView.orientation = .horizontal
        buttonStackView.spacing = 8
        buttonStackView.distribution = .fillEqually
        containerView.addSubview(buttonStackView)
        
        applyButton = NSButton(title: "Apply", target: self, action: #selector(applyCorrection))
        applyButton.bezelStyle = .rounded
        applyButton.isEnabled = false
        buttonStackView.addArrangedSubview(applyButton)
        
        rewordButton = NSButton(title: "Reword", target: self, action: #selector(rewordSentence))
        rewordButton.bezelStyle = .rounded
        buttonStackView.addArrangedSubview(rewordButton)
        
        dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismissWidget))
        dismissButton.bezelStyle = .rounded
        buttonStackView.addArrangedSubview(dismissButton)
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        originalLabel.translatesAutoresizingMaskIntoConstraints = false
        suggestionLabel.translatesAutoresizingMaskIntoConstraints = false
        suggestionsStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            originalLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            originalLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            originalLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            suggestionLabel.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: 8),
            suggestionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            suggestionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            suggestionsStackView.topAnchor.constraint(equalTo: suggestionLabel.bottomAnchor, constant: 8),
            suggestionsStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            suggestionsStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            buttonStackView.topAnchor.constraint(equalTo: suggestionsStackView.bottomAnchor, constant: 12),
            buttonStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            buttonStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            buttonStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            buttonStackView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    func checkGrammar(_ text: String) {
        guard !text.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if let result = self.backend.checkGrammar(text) {
                DispatchQueue.main.async {
                    self.showResult(result, original: text)
                }
            }
        }
    }
    
    func rewordForClarity(_ text: String) {
        guard !text.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let rewrites: [(String, String)] = [
                ("In order to", "To"),
                ("Due to the fact that", "Because"),
                ("At this point in time", "Now"),
                ("In the event that", "If"),
                ("With regard to", "About"),
                ("A large number of", "Many"),
                ("The reason is because", "Because"),
                ("Has the ability to", "Can"),
                ("It is necessary that", "Must"),
                ("In spite of the fact that", "Although"),
                ("Take into consideration", "Consider"),
                ("Come to the conclusion", "Conclude"),
                ("Make a decision", "Decide"),
                ("Give consideration to", "Consider"),
                ("Has a tendency to", "Tends to")
            ]
            
            var rewritten = text
            var suggestions: [String] = []
            
            for (original, replacement) in rewrites {
                if rewritten.lowercased().contains(original.lowercased()) {
                    rewritten = rewritten.replacingOccurrences(
                        of: original,
                        with: replacement,
                        options: .caseInsensitive
                    )
                    suggestions.append("'\(original)' → '\(replacement)'")
                }
            }
            
            let result = GrammarResult(
                original: text,
                corrected: rewritten,
                suggestions: suggestions,
                confidence: 0.8
            )
            
            DispatchQueue.main.async {
                self.showResult(result, original: text)
            }
        }
    }
    
    private func showResult(_ result: GrammarResult, original: String) {
        currentResult = result
        
        originalLabel.stringValue = "Original: \"\(original)\""
        suggestionLabel.stringValue = result.corrected
        
        for view in suggestionsStackView.arrangedSubviews {
            suggestionsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        for suggestion in result.suggestions.prefix(3) {
            let label = NSTextField(labelWithString: suggestion)
            label.font = NSFont.systemFont(ofSize: 10)
            label.textColor = NSColor.secondaryLabelColor
            suggestionsStackView.addArrangedSubview(label)
        }
        
        applyButton.isEnabled = result.corrected != original
        title = "Grammar Check (\(Int(result.confidence * 100))% confidence)"
        
        var frame = self.frame
        let height = suggestionsStackView.arrangedSubviews.isEmpty ? 100.0 : 120.0
        frame.size.height = height
        setFrame(frame, display: true)
    }
    
    func show(at position: NSPoint) {
        setFrameOrigin(position)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
    
    @objc private func applyCorrection() {
        guard let result = currentResult else { return }
        
        if injectText(result.corrected) {
            grammarDelegate?.grammarWidget(self, didCorrect: result.corrected, suggestions: result.suggestions)
            orderOut(nil)
        }
    }
    
    @objc private func rewordSentence() {
        guard let result = currentResult else { return }
        rewordForClarity(result.original)
    }
    
    @objc private func dismissWidget() {
        orderOut(nil)
        grammarDelegate?.grammarWidgetDidDismiss(self)
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
