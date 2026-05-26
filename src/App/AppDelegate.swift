import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: TabyrusEnvironment?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var modelMenuItem: NSMenuItem?
    private var modelMenuRef: NSMenu?
    private var statusRefreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let env = TabyrusEnvironment()
        self.environment = env

        print("Tabyrus - Hardware: \(env.hardwareInfo.modelName) with \(String(format: "%.1f", env.hardwareInfo.ramGB))GB RAM")
        setupStatusBar(env: env)

        guard env.permissionManager.accessibilityGranted else {
            env.permissionManager.requestAccessibility()
            return
        }

        env.startAll()

        let anyDownloaded = TabyrusModel.allCases.contains { env.modelManager.isModelDownloaded($0) }
        if !anyDownloaded {
            promptFirstLaunchDownload(env: env)
        }

        print("Tabyrus started - model: \(env.settingsManager.currentSettings.selectedModel.displayName)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.stopAll()
        statusRefreshTimer?.invalidate()
    }

    private func promptFirstLaunchDownload(env: TabyrusEnvironment) {
        let alert = NSAlert()
        alert.messageText = "Welcome to Tabyrus"
        alert.informativeText = """
        No AI model is downloaded yet. Tabyrus needs a local model for autocomplete, grammar checking, and code reshaping.

        Recommended: Gemma 4 (fast, balanced, ~3.6 GB)
        Lightweight: Qwen 3.5 0.8B (~0.5 GB)

        Would you like to download a model now?
        """
        alert.addButton(withTitle: "Download Recommended (Gemma 4)")
        alert.addButton(withTitle: "Download Lightweight (Qwen 3.5)")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            env.modelManager.downloadModel(.gemma4)
        case .alertSecondButtonReturn:
            env.modelManager.downloadModel(.qwen35)
        default:
            break
        }
    }

    private func setupStatusBar(env: TabyrusEnvironment) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Tabyrus"
        statusItem.button?.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "Tabyrus Autocomplete", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        refreshAll()
        statusMenuItem = NSMenuItem(title: "Status: ...", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)

        modelMenuItem = NSMenuItem(title: "Model: ...", action: nil, keyEquivalent: "")
        modelMenuItem?.isEnabled = false
        menu.addItem(modelMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = env.suggestionCoordinator.isGloballyEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        let modelMenu = buildModelMenu(env: env)
        self.modelMenuRef = modelMenu
        let modelItem = NSMenuItem(title: "AI Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())

        let grammarItem = NSMenuItem(title: "Grammar Check", action: #selector(toggleGrammar), keyEquivalent: "")
        grammarItem.target = self
        grammarItem.state = env.settingsManager.currentSettings.grammarCheckEnabled ? .on : .off
        menu.addItem(grammarItem)

        let reshapeItem = NSMenuItem(title: "Code Reshape", action: #selector(toggleCodeReshape), keyEquivalent: "")
        reshapeItem.target = self
        reshapeItem.state = env.settingsManager.currentSettings.codeReshapeEnabled ? .on : .off
        menu.addItem(reshapeItem)

        menu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "Clear Data", action: #selector(clearData), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem

        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    private func buildModelMenu(env: TabyrusEnvironment) -> NSMenu {
        let menu = NSMenu()
        for model in TabyrusModel.allCases {
            let downloaded = env.modelManager.isModelDownloaded(model)
            let prefix = downloaded ? "✓" : "○"
            let suffix = downloaded ? "" : " (click to download)"
            let item = NSMenuItem(title: "\(prefix) \(model.displayName)\(suffix)", action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            item.state = model == env.settingsManager.currentSettings.selectedModel ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let dlItem = NSMenuItem(title: "Download All Models...", action: #selector(downloadAllModels), keyEquivalent: "")
        dlItem.target = self
        menu.addItem(dlItem)
        return menu
    }

    private func refreshAll() {
        refreshStatusText()
        refreshModelMenu()
    }

    private func refreshStatusText() {
        guard let env = environment, let s = statusMenuItem, let m = modelMenuItem else { return }

        if env.modelManager.isDownloading {
            s.title = "Status: Downloading \(env.modelManager.downloadingModelName) (\(Int(env.modelManager.downloadPercent))%)"
        } else {
            let current = env.settingsManager.currentSettings.selectedModel
            let downloaded = env.modelManager.isModelDownloaded(current)
            s.title = downloaded ? "Status: Ready" : "Status: No model downloaded"
        }
        m.title = "Model: \(env.settingsManager.currentSettings.selectedModel.displayName)"
    }

    private func refreshModelMenu() {
        guard let env = environment, let modelMenu = modelMenuRef else { return }
        for item in modelMenu.items {
            guard let model = item.representedObject as? TabyrusModel else { continue }
            let downloaded = env.modelManager.isModelDownloaded(model)
            let prefix = downloaded ? "✓" : "○"
            let suffix: String
            if env.modelManager.isDownloading && env.modelManager.downloadingModelName == model.displayName {
                suffix = " (downloading...)"
            } else if downloaded {
                suffix = ""
            } else {
                suffix = " (click to download)"
            }
            item.title = "\(prefix) \(model.displayName)\(suffix)"
        }
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        guard let env = environment else { return }
        let newState = !env.suggestionCoordinator.isGloballyEnabled
        env.suggestionCoordinator.isGloballyEnabled = newState
        sender.state = newState ? .on : .off
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let env = environment, let model = sender.representedObject as? TabyrusModel else { return }

        if !env.modelManager.isModelDownloaded(model) {
            env.modelManager.downloadModel(model)
        }

        env.settingsManager.setModel(model)
        for item in sender.menu?.items ?? [] {
            item.state = item == sender ? .on : .off
        }
        env.suggestionCoordinator.prepareForModelSwitch()
        refreshAll()
    }

    @objc private func downloadAllModels() {
        environment?.modelManager.downloadAllModels()
    }

    @objc private func toggleGrammar(_ sender: NSMenuItem) {
        guard let env = environment else { return }
        let newState = !env.settingsManager.currentSettings.grammarCheckEnabled
        env.settingsManager.setGrammarCheckEnabled(newState)
        sender.state = newState ? .on : .off
    }

    @objc private func toggleCodeReshape(_ sender: NSMenuItem) {
        guard let env = environment else { return }
        let newState = !env.settingsManager.currentSettings.codeReshapeEnabled
        env.settingsManager.setCodeReshapeEnabled(newState)
        sender.state = newState ? .on : .off
    }

    @objc private func clearData() {
        environment?.clipboardMonitor.clearHistory()
        environment?.screenshotMonitor.clearHistory()
        environment?.appCustomizationManager.clearAllCustomizations()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
