//
//  AutoCompleteApp.swift
//  Otto
//
//  System-wide autocomplete daemon using macOS Accessibility APIs
//

import SwiftUI

@main
struct AutoCompleteDaemon: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No UI - runs as background service
        Settings {
            EmptyView()
        }
    }
}