//
//  CompletionWindow.swift
//  Otto
//
//  Floating completion window for system-wide suggestions
//

import Cocoa

class CompletionWindow: NSWindow {
    private var suggestionLabel: NSTextField!
    private var currentSuggestion: String = ""

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        setupWindow()
        setupUI()
    }

    private func setupWindow() {
        // Configure as floating, non-interactive overlay
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        // Don't appear in window lists
        setFrameAutosaveName("")
    }

    private func setupUI() {
        guard let contentView = contentView else { return }

        // Create suggestion label
        suggestionLabel = NSTextField(frame: contentView.bounds)
        suggestionLabel.isEditable = false
        suggestionLabel.isBordered = false
        suggestionLabel.backgroundColor = .clear
        suggestionLabel.textColor = NSColor.systemGray
        suggestionLabel.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        suggestionLabel.alphaValue = 0.7
        suggestionLabel.maximumNumberOfLines = 1
        suggestionLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(suggestionLabel)
        suggestionLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            suggestionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            suggestionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            suggestionLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func show(at position: NSPoint, suggestion: String) {
        currentSuggestion = suggestion
        suggestionLabel.stringValue = suggestion

        // Position window near cursor
        let windowSize = NSSize(width: min(300, suggestionLabel.intrinsicContentSize.width + 16), height: 40)
        let windowRect = NSRect(origin: position, size: windowSize)

        setFrame(windowRect, display: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    func acceptCompletion() -> Bool {
        guard !currentSuggestion.isEmpty else { return false }

        // Use accessibility to insert text into the focused element
        injectTextViaAccessibility(currentSuggestion)
        hide()
        currentSuggestion = ""
        return true
    }

    private func injectTextViaAccessibility(_ text: String) {
        // Get the currently focused accessibility element
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else {
            // Fallback to CGEvent injection
            injectTextViaEvents(text)
            return
        }
        
        // Try to insert text using accessibility
        let textValue = text as CFString
        let insertResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, textValue)
        
        if insertResult != .success {
            // If direct insertion fails, try CGEvent approach
            injectTextViaEvents(text)
        }
    }

    private func injectTextViaEvents(_ text: String) {
        // Use CGEvent to inject keystrokes
        for character in text {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                let uniChar = UniChar(character.unicodeScalars.first?.value ?? 0)
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [uniChar])
                
                event.post(tap: .cgSessionEventTap)
            }
            
            // Small delay between characters
            usleep(1000)
        }
    }
}