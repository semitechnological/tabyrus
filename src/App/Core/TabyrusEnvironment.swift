import Foundation
import Combine

@MainActor
final class TabyrusEnvironment {
    let backend: TabyrusBackend
    let settingsManager: TabyrusSettingsManager
    let permissionManager: PermissionManager
    let hardwareInfo: HardwareInfo
    let focusTracker: FocusTracker
    let inputMonitor: InputMonitor
    let suggestionCoordinator: SuggestionCoordinator
    let clipboardMonitor: ClipboardMonitor
    let screenshotMonitor: ScreenshotMonitor
    let appCustomizationManager: AppCustomizationManager
    let codeReshapeService: CodeReshapeService
    let modelManager: ModelManager
    let suggestionEngine: TabyrusSuggestionEngine

    private var cancellables = Set<AnyCancellable>()

    init() {
        backend = TabyrusBackend.shared
        settingsManager = TabyrusSettingsManager.shared
        permissionManager = PermissionManager()
        hardwareInfo = HardwareDetector.detectHardware()
        focusTracker = FocusTracker()
        modelManager = ModelManager(backend: backend)
        suggestionEngine = TabyrusSuggestionEngine(backend: backend)
        inputMonitor = InputMonitor()

        let aiService = CombinedAIService(hardwareInfo: hardwareInfo)
        suggestionCoordinator = SuggestionCoordinator(
            engine: suggestionEngine,
            focusProvider: focusTracker,
            inputMonitor: inputMonitor,
            settings: settingsManager
        )
        clipboardMonitor = ClipboardMonitor()
        screenshotMonitor = ScreenshotMonitor()
        appCustomizationManager = AppCustomizationManager(aiService: aiService)
        codeReshapeService = CodeReshapeService(backend: backend)

        permissionManager.$accessibilityGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.focusTracker.refreshNow()
            }
            .store(in: &cancellables)

        permissionManager.$inputMonitoringGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.inputMonitor.refresh()
            }
            .store(in: &cancellables)
    }

    func startAll() {
        focusTracker.start()
        inputMonitor.start()
        suggestionCoordinator.start()
        clipboardMonitor.startMonitoring()
    }

    func stopAll() {
        suggestionCoordinator.stop()
        inputMonitor.stop()
        focusTracker.stop()
        clipboardMonitor.stopMonitoring()
        screenshotMonitor.stopMonitoring()
    }
}
