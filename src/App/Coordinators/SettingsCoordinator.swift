import Combine

@MainActor
final class SettingsCoordinator: ObservableObject {
    private let settings: TabyrusSettingsManager
    private let modelManager: ModelManager
    private let suggestionCoordinator: SuggestionCoordinator

    @Published var selectedModel: TabyrusModel
    @Published var isGrammarEnabled: Bool
    @Published var isCodeReshapeEnabled: Bool

    private var cancellables = Set<AnyCancellable>()

    init(settings: TabyrusSettingsManager, modelManager: ModelManager, suggestionCoordinator: SuggestionCoordinator) {
        self.settings = settings
        self.modelManager = modelManager
        self.suggestionCoordinator = suggestionCoordinator

        let current = settings.currentSettings
        self.selectedModel = current.selectedModel
        self.isGrammarEnabled = current.grammarCheckEnabled
        self.isCodeReshapeEnabled = current.codeReshapeEnabled

        $selectedModel
            .dropFirst()
            .sink { [weak self] model in
                self?.settings.setModel(model)
                self?.suggestionCoordinator.prepareForModelSwitch()
            }
            .store(in: &cancellables)

        $isGrammarEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.settings.setGrammarCheckEnabled(enabled)
            }
            .store(in: &cancellables)

        $isCodeReshapeEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.settings.setCodeReshapeEnabled(enabled)
            }
            .store(in: &cancellables)
    }

    var availableModels: [TabyrusModel] {
        TabyrusModel.allCases
    }

    func isModelDownloaded(_ model: TabyrusModel) -> Bool {
        modelManager.isModelDownloaded(model)
    }
}
