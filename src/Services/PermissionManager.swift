import AppKit
import Combine

@MainActor
final class PermissionManager: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var screenRecordingGranted = false

    init() {
        refreshAll()
    }

    func refreshAll() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = checkInputMonitoring()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkInputMonitoring() -> Bool {
        let testEvent = CGEvent(source: nil)
        return testEvent != nil
    }
}
