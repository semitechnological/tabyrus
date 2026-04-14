//
//  AccessibilityMonitor.swift
//  Otto
//
//  Monitors system-wide text input using macOS Accessibility APIs
//

import Foundation
import ApplicationServices
import AppKit
import OttoBackend

class AccessibilityMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var completionWindow: CompletionWindow?

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        print("Starting accessibility monitoring...")

        // Check accessibility permissions
        guard AXIsProcessTrusted() else {
            print("Accessibility permissions required. Please enable in System Preferences > Security & Privacy > Accessibility")
            requestAccessibilityPermission()
            return
        }

        // Create completion window
        completionWindow = CompletionWindow()

        // Set up global event tap for key events
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
                       CGEventMask(1 << CGEventType.keyUp.rawValue) |
                       CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if let eventTap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            print("Accessibility monitoring started successfully")
        } else {
            print("Failed to create event tap - accessibility permissions may be required")
        }
    }

    func stopMonitoring() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
        }
        completionWindow?.hide()
    }

    private func requestAccessibilityPermission() {
        print("Accessibility permissions required. Opening System Preferences...")
        
        // Open System Preferences to Accessibility pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        
        // Also show a notification if possible
        let notification = NSUserNotification()
        notification.title = "Accessibility Permission Required"
        notification.informativeText = "Otto needs accessibility permissions to provide system-wide autocomplete. Please enable it in System Preferences > Security & Privacy > Accessibility, then restart Otto."
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }

    func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check for Tab key (keycode 48) without modifier keys for completion acceptance
        if keyCode == 48 && flags.isEmpty {
            if completionWindow?.acceptCompletion() == true {
                // Completion was accepted, suppress the tab key
                return nil
            }
        }

        // Monitor text input changes
        checkForTextInputChanges()

        return event
    }

    private func checkForTextInputChanges() {
        // Get the currently focused accessibility element
        guard let focusedElement = getFocusedElement() else { return }

        // Get text content and cursor position
        if let textContent = getTextContent(from: focusedElement),
           let cursorPosition = getCursorPosition(from: focusedElement) {

            // Get completion suggestion
            if let suggestion = getCompletionFor(text: textContent, cursorPosition: cursorPosition) {
                showCompletion(at: cursorPosition, suggestion: suggestion, in: focusedElement)
            } else {
                completionWindow?.hide()
            }
        }
    }

    private func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let element = focusedElement {
            return (element as! AXUIElement)
        }
        return nil
    }

    private func getTextContent(from element: AXUIElement) -> String? {
        var textValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)

        if result == .success, let text = textValue as? String {
            return text
        }
        return nil
    }

    private func getCursorPosition(from element: AXUIElement) -> NSPoint? {
        // Get the bounds of the focused element instead of trying to get cursor position
        // This is simpler and works for most text input scenarios
        var bounds: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &bounds)
        
        if result == .success, let point = bounds as? NSPoint {
            // Get size as well
            var size: CFTypeRef?
            let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
            
            if sizeResult == .success, let elementSize = size as? NSSize {
                // Return position at the bottom-left of the element (typical cursor position)
                return NSPoint(x: point.x, y: point.y + elementSize.height)
            }
        }
        return nil
    }

    private func getCompletionFor(text: String, cursorPosition: NSPoint) -> String? {
        // Use Rust backend for completion
        let backend = OttoBackend.shared
        return backend.getCompletion(for: text)?.suggestion
    }

    private func showCompletion(at position: NSPoint, suggestion: String, in element: AXUIElement) {
        completionWindow?.show(at: position, suggestion: suggestion)
    }
}

func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }

    let monitor = Unmanaged<AccessibilityMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .keyDown {
        if let result = monitor.handleKeyEvent(event) {
            return Unmanaged.passUnretained(result)
        } else {
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}