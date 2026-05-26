import Foundation

final class ModelManager: ObservableObject {
    private let backend: TabyrusBackend

    @Published var availableModels: [TabyrusModel] = TabyrusModel.allCases
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloading = false
    @Published var currentStatus: String = "Checking..."
    @Published var downloadPercent: Double = 0
    @Published var downloadingModelName: String = ""

    init(backend: TabyrusBackend) {
        self.backend = backend
        refreshStatus()
    }

    func isModelDownloaded(_ model: TabyrusModel) -> Bool {
        backend.isModelDownloaded(model.modelIdentifier)
    }

    func downloadModel(_ model: TabyrusModel) {
        guard !isModelDownloaded(model) else { return }
        isDownloading = true
        downloadingModelName = model.displayName
        downloadPercent = 0
        currentStatus = "Downloading \(model.displayName)..."
        objectWillChange.send()

        let estimatedSize = model.estimatedSizeMB

        backend.downloadModel(model.modelIdentifier) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isDownloading = false
                self.downloadingModelName = ""

                switch result {
                case .success(let r):
                    self.downloadPercent = 100
                    self.downloadProgress[model.modelIdentifier] = 100
                case .failure(let e):
                    self.downloadPercent = 0
                    print("Download failed: \(e.localizedDescription)")
                }

                self.refreshStatus()
                self.objectWillChange.send()
            }
        }

        downloadProgress[model.modelIdentifier] = 0
        simulateProgress(for: model, estimatedSizeMB: estimatedSize)
    }

    private func simulateProgress(for model: TabyrusModel, estimatedSizeMB: Double) {
        guard estimatedSizeMB > 0 else { return }

        let totalSteps = 20
        let stepInterval = 1.5
        var step = 0

        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }

                if !self.isDownloading || self.downloadingModelName != model.displayName {
                    timer.invalidate()
                    return
                }

                step += 1
                let percent = min(Double(step) / Double(totalSteps) * 95.0, 95.0)
                self.downloadPercent = percent
                self.downloadProgress[model.modelIdentifier] = percent
                self.objectWillChange.send()
            }
        }
    }

    func downloadAllModels() {
        for model in TabyrusModel.allCases where !isModelDownloaded(model) {
            downloadModel(model)
        }
    }

    func modelCachePath(for model: TabyrusModel) -> String? {
        backend.getModelCachePath(model.modelIdentifier)
    }

    func refreshStatus() {
        let downloaded = TabyrusModel.allCases.filter { isModelDownloaded($0) }
        if isDownloading {
            currentStatus = "Downloading \(downloadingModelName) (\(Int(downloadPercent))%)"
        } else if downloaded.isEmpty {
            currentStatus = "No model"
        } else {
            currentStatus = "Ready"
        }
    }
}
