//
//  ClipboardMonitor.swift
//  Otto
//
//  Monitors clipboard contents and stores them for AI context
//

import Cocoa
import Foundation

class ClipboardMonitor {
    private var timer: Timer?
    private var lastClipboardContent: String = ""
    private var clipboardHistory: [(timestamp: Date, content: String, app: String)] = []
    private let maxHistoryItems = 100
    
    // Delegate to notify when clipboard changes
    weak var delegate: ClipboardMonitorDelegate?
    
    init() {
        // Start monitoring immediately
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        // Check clipboard every 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        print("Clipboard monitoring started")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("Clipboard monitoring stopped")
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Check for string content
        if let stringContent = pasteboard.string(forType: .string) {
            if stringContent != lastClipboardContent && !stringContent.isEmpty {
                lastClipboardContent = stringContent
                
                // Get current app info
                let currentApp = getCurrentApplicationName()
                
                // Store in history
                let entry = (timestamp: Date(), content: stringContent, app: currentApp)
                clipboardHistory.append(entry)
                
                // Keep only recent items
                if clipboardHistory.count > maxHistoryItems {
                    clipboardHistory.removeFirst(clipboardHistory.count - maxHistoryItems)
                }
                
                // Notify delegate
                delegate?.clipboardDidChange(content: stringContent, app: currentApp)
                
                print("Clipboard updated: \(stringContent.prefix(50))... from \(currentApp)")
            }
        }
    }
    
    private func getCurrentApplicationName() -> String {
        // Get the currently active application
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            return frontmostApp.localizedName ?? frontmostApp.bundleIdentifier ?? "Unknown"
        }
        return "Unknown"
    }
    
    // Get recent clipboard history for a specific app
    func getClipboardHistory(for app: String, limit: Int = 10) -> [String] {
        return clipboardHistory
            .filter { $0.app == app }
            .suffix(limit)
            .map { $0.content }
    }
    
    // Get all clipboard history (for AI context)
    func getAllClipboardHistory(limit: Int = 50) -> [(timestamp: Date, content: String, app: String)] {
        return Array(clipboardHistory.suffix(limit))
    }
    
    // Clear history
    func clearHistory() {
        clipboardHistory.removeAll()
        lastClipboardContent = ""
        print("Clipboard history cleared")
    }
}

protocol ClipboardMonitorDelegate: AnyObject {
    func clipboardDidChange(content: String, app: String)
}