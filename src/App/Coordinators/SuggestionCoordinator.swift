import Combine
import Cocoa

final class SuggestionCoordinator: ObservableObject {
    private let engine: TabyrusSuggestionEngine
    private let focusProvider: FocusTracker
    private let inputMonitor: InputMonitor
    private let settings: TabyrusSettingsManager
    private let overlay: CompletionOverlay

    @Published var isGloballyEnabled = true
    @Published var activeSuggestion: String?
    @Published var suggestionPreview: String?

    private var cancellables = Set<AnyCancellable>()
    private var generationTask: Task<Void, Never>?
    private var lastProcessedText: String?

    init(
        engine: TabyrusSuggestionEngine,
        focusProvider: FocusTracker,
        inputMonitor: InputMonitor,
        settings: TabyrusSettingsManager
    ) {
        self.engine = engine
        self.focusProvider = focusProvider
        self.inputMonitor = inputMonitor
        self.settings = settings
        self.overlay = CompletionOverlay()

        setupSubscriptions()
    }

    private func setupSubscriptions() {
        focusProvider.$snapshot
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.handleFocusChange(snapshot)
            }
            .store(in: &cancellables)

        inputMonitor.tabPressedHandler = { [weak self] in
            self?.acceptSuggestion() ?? false
        }
    }

    func start() {
        overlay.hide()
    }

    func stop() {
        generationTask?.cancel()
        overlay.hide()
        activeSuggestion = nil
    }

    private func handleFocusChange(_ snapshot: FocusSnapshot) {
        guard isGloballyEnabled,
              let context = snapshot.context,
              !context.textValue.isEmpty else {
            overlay.hide()
            activeSuggestion = nil
            return
        }

        guard shouldGenerate(for: context.textValue) else {
            overlay.hide()
            activeSuggestion = nil
            return
        }

        lastProcessedText = context.textValue

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await self.generateSuggestion(for: context)
        }
    }

    private func shouldGenerate(for text: String) -> Bool {
        return SuggestionAvailabilityEvaluator.shouldGenerate(for: text)
    }

    private func generateSuggestion(for context: FocusedContext) async {
        guard !Task.isCancelled else { return }

        let clippedText = truncateToRelevantText(context.textValue)

        let suggestion = engine.generate(for: clippedText)

        guard !Task.isCancelled else { return }

        await MainActor.run {
            if let suggestion {
                let formatted = SuggestionTextNormalizer.normalize(suggestion.text)
                activeSuggestion = formatted
                overlay.show(
                    suggestion: SuggestionTextNormalizer.formatGhostText(formatted, relativeTo: clippedText),
                    at: context.caretRect,
                    in: context.inputFrameRect
                )
            } else {
                activeSuggestion = nil
                overlay.hide()
            }
        }
    }

    private func truncateToRelevantText(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        let maxWords = 50
        if words.count > maxWords {
            return words.suffix(maxWords).joined(separator: " ")
        }
        return text
    }

    func acceptSuggestion() -> Bool {
        guard let context = focusProvider.snapshot.context,
              let suggestion = activeSuggestion else { return false }

        guard injectText(suggestion, into: context.element) else {
            return false
        }

        overlay.hide()
        activeSuggestion = nil
        lastProcessedText = nil
        return true
    }

    private func injectText(_ text: String, into element: AXUIElement) -> Bool {
        let selectedTextResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        if selectedTextResult == .success {
            return true
        }

        var textValueRef: CFTypeRef?
        let textValueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValueRef)
        guard textValueResult == .success,
              let currentValue = textValueRef as? String else { return false }

        var selectedRangeRef: CFTypeRef?
        var selectedRange: NSRange?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
           let selectedRangeRef {
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(selectedRangeRef as! AXValue, .cfRange, &cfRange) {
                selectedRange = NSRange(location: cfRange.location, length: cfRange.length)
            }
        }

        let newValue = SuggestionAcceptance.textByApplyingInsertion(text, to: currentValue, selectedRange: selectedRange)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFString)
        return result == .success
    }

    func prepareForModelSwitch() {
        generationTask?.cancel()
        activeSuggestion = nil
        overlay.hide()
    }
}
