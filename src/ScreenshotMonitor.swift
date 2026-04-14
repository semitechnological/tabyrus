//
//  ScreenshotMonitor.swift
//  Otto
//
//  Captures screenshots for visual context and AI processing
//

import Cocoa
import CoreGraphics
import Foundation

class ScreenshotMonitor {
    private var timer: Timer?
    private var screenshotHistory: [(timestamp: Date, image: NSImage, app: String)] = []
    private let maxScreenshots = 20
    private let screenshotInterval: TimeInterval = 30.0 // 30 seconds
    
    // Delegate for screenshot events
    weak var delegate: ScreenshotMonitorDelegate?
    
    init() {
        // Don't start automatically - let user control this for privacy
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: screenshotInterval, repeats: true) { [weak self] _ in
            self?.captureScreenshot()
        }
        print("Screenshot monitoring started (every \(screenshotInterval) seconds)")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("Screenshot monitoring stopped")
    }
    
    func captureScreenshotNow() -> NSImage? {
        return captureScreenshot()
    }
    
    @discardableResult
    private func captureScreenshot() -> NSImage? {
        // Get screen bounds
        guard let screen = NSScreen.main else { return nil }
        let screenRect = screen.frame
        
        // Capture screenshot using CGWindowListCreateImage
        // Note: This API is deprecated in macOS 14+, but still works
        // For production, consider using ScreenCaptureKit with proper entitlements
        let windowListOption = CGWindowListOption.optionOnScreenOnly
        let windowImageOption = CGWindowImageOption.bestResolution
        
        // Suppress deprecation warning - still functional on current macOS
        #if swift(>=5.9)
        guard let cgImage = CGWindowListCreateImage(screenRect, windowListOption, kCGNullWindowID, windowImageOption) else {
            print("Failed to capture screenshot (CGWindowListCreateImage may be restricted)")
            return nil
        }
        #else
        guard let cgImage = CGWindowListCreateImage(screenRect, windowListOption, kCGNullWindowID, windowImageOption) else {
            print("Failed to capture screenshot (CGWindowListCreateImage may be restricted)")
            return nil
        }
        #endif
        
        // Convert to NSImage
        let nsImage = NSImage(cgImage: cgImage, size: screenRect.size)
        
        // Get current app
        let currentApp = getCurrentApplicationName()
        
        // Store in history
        let entry = (timestamp: Date(), image: nsImage, app: currentApp)
        screenshotHistory.append(entry)
        
        // Keep only recent screenshots
        if screenshotHistory.count > maxScreenshots {
            screenshotHistory.removeFirst(screenshotHistory.count - maxScreenshots)
        }
        
        // Notify delegate
        delegate?.screenshotCaptured(image: nsImage, app: currentApp)
        
        print("Screenshot captured for \(currentApp)")
        return nsImage
    }
    
    private func getCurrentApplicationName() -> String {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            return frontmostApp.localizedName ?? frontmostApp.bundleIdentifier ?? "Unknown"
        }
        return "Unknown"
    }
    
    // Get recent screenshots for a specific app
    func getScreenshots(for app: String, limit: Int = 5) -> [NSImage] {
        return screenshotHistory
            .filter { $0.app == app }
            .suffix(limit)
            .map { $0.image }
    }
    
    // Get all recent screenshots
    func getAllScreenshots(limit: Int = 10) -> [(timestamp: Date, image: NSImage, app: String)] {
        return Array(screenshotHistory.suffix(limit))
    }
    
    // Clear screenshot history
    func clearHistory() {
        screenshotHistory.removeAll()
        print("Screenshot history cleared")
    }
    
    // Save screenshot to file (for debugging/analysis)
    func isMonitoring() -> Bool {
        return timer != nil
    }
}

protocol ScreenshotMonitorDelegate: AnyObject {
    func screenshotCaptured(image: NSImage, app: String)
}