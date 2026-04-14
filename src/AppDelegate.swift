//
//  AppDelegate.swift
//  Otto
//
//  Application delegate for the system-wide autocomplete daemon
//

import Cocoa
import ApplicationServices
import OttoBackend

class AppDelegate: NSObject, NSApplicationDelegate, ClipboardMonitorDelegate, ScreenshotMonitorDelegate, GrammarWidgetDelegate, CodeReshapeServiceDelegate {
    var statusItem: NSStatusItem?
    var accessibilityMonitor: AccessibilityMonitor?
    var clipboardMonitor: ClipboardMonitor?
    var screenshotMonitor: ScreenshotMonitor?
    var hardwareInfo: HardwareInfo?
    var aiService: CombinedAIService?
    var appCustomizationManager: AppCustomizationManager?
    
    var grammarWidget: GrammarWidget?
    var codeReshapeService: CodeReshapeService?
    var settingsManager: OttoSettingsManager { OttoSettingsManager.shared }
    
    private var statusMenuItems: [Int: NSMenuItem] = [:]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        hardwareInfo = HardwareDetector.detectHardware()
        print("Hardware detected: \(hardwareInfo?.modelName ?? "Unknown") with \(hardwareInfo?.ramGB ?? 0)GB RAM")
        
        if let hardwareInfo = hardwareInfo {
            aiService = CombinedAIService(hardwareInfo: hardwareInfo)
            appCustomizationManager = AppCustomizationManager(aiService: aiService)
        }
        
        codeReshapeService = CodeReshapeService()
        codeReshapeService?.delegate = self
        
        _ = OttoSettingsManager.shared
        
        setupStatusBar()
        setupAccessibility()
        setupMonitors()
        
        print("Otto Autocomplete Daemon started")
        print("Using \(hardwareInfo?.recommendedModelSize ?? "unknown") model configuration")
        print("Selected AI model: \(settingsManager.currentSettings.selectedModel.displayName)")
        
        if settingsManager.currentSettings.codeReshapeEnabled {
            print("Code reshaping: enabled (\(settingsManager.currentSettings.codeReshapeBehavior.displayName))")
        }
        if settingsManager.currentSettings.grammarCheckEnabled {
            print("Grammar checking: enabled")
        }
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "Otto"

        let menu = NSMenu()
        
        let aboutItem = NSMenuItem(title: "About Otto", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.tag = 100
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let monitoringItem = NSMenuItem(title: "Monitoring: On", action: #selector(toggleMonitoring), keyEquivalent: "")
        monitoringItem.tag = 1
        statusMenuItems[1] = monitoringItem
        menu.addItem(monitoringItem)
        
        let clipboardItem = NSMenuItem(title: "Clipboard: On", action: #selector(toggleClipboard), keyEquivalent: "")
        clipboardItem.tag = 2
        statusMenuItems[2] = clipboardItem
        menu.addItem(clipboardItem)
        
        let screenshotItem = NSMenuItem(title: "Screenshots: Off", action: #selector(toggleScreenshots), keyEquivalent: "")
        screenshotItem.tag = 3
        statusMenuItems[3] = screenshotItem
        menu.addItem(screenshotItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let modelSubmenu = NSMenu()
        let modelItem = NSMenuItem(title: "AI Model", action: nil, keyEquivalent: "")
        modelItem.tag = 10
        for model in OttoModel.allCases {
            let item = NSMenuItem(
                title: model.displayName,
                action: #selector(selectModel(_:)),
                keyEquivalent: ""
            )
            item.representedObject = model
            item.state = model == settingsManager.currentSettings.selectedModel ? .on : .off
            modelSubmenu.addItem(item)
        }
        modelItem.submenu = modelSubmenu
        menu.addItem(modelItem)
        
        let reshapeEnabledItem = NSMenuItem(
            title: "Code Reshaping",
            action: #selector(toggleCodeReshape),
            keyEquivalent: ""
        )
        reshapeEnabledItem.tag = 11
        reshapeEnabledItem.state = settingsManager.currentSettings.codeReshapeEnabled ? .on : .off
        menu.addItem(reshapeEnabledItem)
        
        if settingsManager.currentSettings.codeReshapeEnabled {
            let reshapeSubmenu = NSMenu()
            let reshapeBehaviorItem = NSMenuItem(title: "Reshape Behavior", action: nil, keyEquivalent: "")
            for behavior in OttoSettings.CodeReshapeBehavior.allCases {
                let item = NSMenuItem(
                    title: behavior.displayName,
                    action: #selector(selectReshapeBehavior(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = behavior
                item.state = behavior == settingsManager.currentSettings.codeReshapeBehavior ? .on : .off
                reshapeSubmenu.addItem(item)
            }
            reshapeBehaviorItem.submenu = reshapeSubmenu
            menu.addItem(reshapeBehaviorItem)
        }
        
        let grammarEnabledItem = NSMenuItem(
            title: "Grammar Check",
            action: #selector(toggleGrammarCheck),
            keyEquivalent: ""
        )
        grammarEnabledItem.tag = 12
        grammarEnabledItem.state = settingsManager.currentSettings.grammarCheckEnabled ? .on : .off
        menu.addItem(grammarEnabledItem)
        
        let grammarShortcutItem = NSMenuItem(
            title: "Check Grammar (Ctrl+Shift+G)",
            action: #selector(showGrammarWidget),
            keyEquivalent: ""
        )
        grammarShortcutItem.tag = 13
        menu.addItem(grammarShortcutItem)
        
        let reshapeShortcutItem = NSMenuItem(
            title: "Reshape Code (Ctrl+Shift+R)",
            action: #selector(showCodeReshape),
            keyEquivalent: ""
        )
        reshapeShortcutItem.tag = 14
        menu.addItem(reshapeShortcutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let clearDataItem = NSMenuItem(title: "Clear Data", action: #selector(clearData), keyEquivalent: "")
        clearDataItem.tag = 20
        menu.addItem(clearDataItem)
        
        let resetSettingsItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetSettings), keyEquivalent: "")
        resetSettingsItem.tag = 21
        menu.addItem(resetSettingsItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    func setupAccessibility() {
        accessibilityMonitor = AccessibilityMonitor()
        accessibilityMonitor?.startMonitoring()
    }
    
    func setupMonitors() {
        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.delegate = self
        
        screenshotMonitor = ScreenshotMonitor()
        screenshotMonitor?.delegate = self
        
        print("Monitors initialized")
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Otto Autocomplete"
        alert.informativeText = """
        System-wide AI autocomplete with zeta-2 and Qwen support
        
        Features:
        • AI-powered autocomplete (zeta-2, Qwen 3.5)
        • Code reshaping/refactoring
        • Grammar checking
        • Sentence rewording
        
        Keyboard shortcuts:
        • Tab: Accept completion
        • Ctrl+Shift+G: Check grammar
        • Ctrl+Shift+R: Reshape code
        """
        alert.runModal()
    }

    @objc func toggleMonitoring() {
        if accessibilityMonitor != nil {
            accessibilityMonitor?.stopMonitoring()
            accessibilityMonitor = nil
            statusMenuItems[1]?.title = "Monitoring: Off"
            print("Otto monitoring stopped")
        } else {
            accessibilityMonitor = AccessibilityMonitor()
            accessibilityMonitor?.startMonitoring()
            statusMenuItems[1]?.title = "Monitoring: On"
            print("Otto monitoring started")
        }
    }

    @objc func toggleClipboard() {
        if clipboardMonitor != nil {
            clipboardMonitor?.stopMonitoring()
            clipboardMonitor = nil
            statusMenuItems[2]?.title = "Clipboard: Off"
            print("Clipboard monitoring stopped")
        } else {
            clipboardMonitor = ClipboardMonitor()
            clipboardMonitor?.delegate = self
            statusMenuItems[2]?.title = "Clipboard: On"
            print("Clipboard monitoring started")
        }
    }

    @objc func toggleScreenshots() {
        if screenshotMonitor?.isMonitoring() == true {
            screenshotMonitor?.stopMonitoring()
            statusMenuItems[3]?.title = "Screenshots: Off"
            print("Screenshot monitoring stopped")
        } else {
            screenshotMonitor?.startMonitoring()
            statusMenuItems[3]?.title = "Screenshots: On"
            print("Screenshot monitoring started")
        }
    }
    
    @objc func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? OttoModel else { return }
        
        settingsManager.setModel(model)
        
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = item == sender ? .on : .off
            }
        }
        
        print("Model switched to: \(model.displayName)")
    }
    
    @objc func toggleCodeReshape() {
        let newState = !settingsManager.currentSettings.codeReshapeEnabled
        settingsManager.setCodeReshapeEnabled(newState)
        statusMenuItems[11]?.state = newState ? .on : .off
        
        rebuildMenu()
        print("Code reshaping \(newState ? "enabled" : "disabled")")
    }
    
    @objc func selectReshapeBehavior(_ sender: NSMenuItem) {
        guard let behavior = sender.representedObject as? OttoSettings.CodeReshapeBehavior else { return }
        
        settingsManager.setCodeReshapeBehavior(behavior)
        
        if let submenu = sender.menu {
            for item in submenu.items {
                item.state = item == sender ? .on : .off
            }
        }
        
        print("Reshape behavior: \(behavior.displayName)")
    }
    
    @objc func toggleGrammarCheck() {
        let newState = !settingsManager.currentSettings.grammarCheckEnabled
        settingsManager.setGrammarCheckEnabled(newState)
        statusMenuItems[12]?.state = newState ? .on : .off
        
        print("Grammar checking \(newState ? "enabled" : "disabled")")
    }
    
    @objc func showGrammarWidget() {
        let selectedText = getSelectedText()
        
        if grammarWidget == nil {
            grammarWidget = GrammarWidget()
            grammarWidget?.grammarDelegate = self
        }
        
        grammarWidget?.center()
        grammarWidget?.makeKeyAndOrderFront(nil)
        
        if !selectedText.isEmpty {
            grammarWidget?.checkGrammar(selectedText)
        }
    }
    
    @objc func showCodeReshape() {
        let selectedText = getSelectedText()
        
        if selectedText.isEmpty {
            print("Select some code to reshape")
            return
        }
        
        codeReshapeService?.reshape(selectedText, operation: .refactor)
    }
    
    private func getSelectedText() -> String {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement as! AXUIElement? else {
            return ""
        }
        
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }
        
        return ""
    }
    
    private func rebuildMenu() {
        statusItem?.menu = nil
        setupStatusBar()
    }

    @objc func clearData() {
        clipboardMonitor?.clearHistory()
        screenshotMonitor?.clearHistory()
        appCustomizationManager?.clearAllCustomizations()
        print("All data cleared")
    }
    
    @objc func resetSettings() {
        settingsManager.resetToDefaults()
        rebuildMenu()
        print("Settings reset to defaults")
    }

    @objc func quitApp() {
        NSApp.terminate(self)
    }
    
    // ClipboardMonitorDelegate
    func clipboardDidChange(content: String, app: String) {
        if let bundleId = getBundleIdentifier(for: app) {
            appCustomizationManager?.updateCustomization(for: bundleId, clipboardContent: content)
        }
        print("Clipboard updated in \(app): \(content.prefix(50))...")
    }
    
    // ScreenshotMonitorDelegate
    func screenshotCaptured(image: NSImage, app: String) {
        print("Screenshot captured in \(app)")
    }
    
    // GrammarWidgetDelegate
    func grammarWidget(_ widget: GrammarWidget, didCorrect text: String, suggestions: [String]) {
        print("Grammar corrected: \(text)")
    }
    
    func grammarWidgetDidDismiss(_ widget: GrammarWidget) {
        print("Grammar widget dismissed")
    }
    
    // CodeReshapeServiceDelegate
    func codeReshapeService(_ service: CodeReshapeService, didSuggestReshape result: CodeReshapeResult, for code: String) {
        let alert = NSAlert()
        alert.messageText = "Code Suggestion (\(Int(result.confidence * 100))% confidence)"
        alert.informativeText = """
        Original:
        \(code)
        
        Suggested:
        \(result.reshaped)
        """
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Dismiss")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = service.applyReshape(result)
            print("Code reshape applied")
        }
    }
    
    func codeReshapeService(_ service: CodeReshapeService, didFailWithError error: Error) {
        print("Code reshape failed: \(error.localizedDescription)")
    }
    
    private func getBundleIdentifier(for appName: String) -> String? {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.localizedName == appName {
            return frontmostApp.bundleIdentifier
        }
        return nil
    }
}
