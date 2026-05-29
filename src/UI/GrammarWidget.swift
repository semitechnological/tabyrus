//
//  GrammarWidget.swift
//  Tabyrus
//
//  Floating widget for grammar checking and sentence rewording
//

import Cocoa
import AppKit
import SwiftUI

protocol GrammarWidgetDelegate: AnyObject {
    func grammarWidget(_ widget: GrammarWidget, didCorrect text: String, suggestions: [String])
    func grammarWidgetDidDismiss(_ widget: GrammarWidget)
}

class GrammarWidget: NSWindow {
    weak var grammarDelegate: GrammarWidgetDelegate?

    private var hostingView: NSHostingView<GrammarWidgetContentView>?
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

        let hostingView = NSHostingView(rootView: contentViewState(original: "", result: nil))
        contentView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.hostingView = hostingView
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
        hostingView?.rootView = contentViewState(original: original, result: result)
        title = "Grammar Check (\(Int(result.confidence * 100))% confidence)"
        
        var frame = self.frame
        let height = result.suggestions.isEmpty ? 128.0 : 156.0
        frame.size.height = height
        setFrame(frame, display: true)
    }

    private func contentViewState(original: String, result: GrammarResult?) -> GrammarWidgetContentView {
        GrammarWidgetContentView(
            original: original,
            result: result,
            onApply: { [weak self] in self?.applyCorrection() },
            onReword: { [weak self] in self?.rewordSentence() },
            onDismiss: { [weak self] in self?.dismissWidget() }
        )
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

private struct GrammarWidgetContentView: View {
    let original: String
    let result: GrammarResult?
    let onApply: () -> Void
    let onReword: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                Text("Original: \"\(original)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text(result.corrected)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if !result.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(result.suggestions.prefix(3)), id: \.self) { suggestion in
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Apply", action: onApply)
                        .disabled(result.corrected == original)
                    Button("Reword", action: onReword)
                    Button("Dismiss", action: onDismiss)
                }
                .buttonStyle(.bordered)
            } else {
                EmptyView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect()
    }
}
