//
//  PreferencesWindowController.swift
//  SmartFan
//
//  Hosts the SwiftUI preferences view in a plain NSWindow. The window is created
//  once and reused; closing it hides rather than destroys, so the app keeps running
//  with only the status item (see docs/menu-bar-display-plan.md §6/§8).
//

import AppKit
import SwiftUI
import SmartFanCore
import SmartFanLocalization

@MainActor
final class PreferencesWindowController {
    private let window: NSWindow

    init(appState: AppState, language: AppLanguageStore) {
        let root = PreferencesView()
            .environmentObject(appState)
            .environmentObject(language)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = language.text("Preferences…")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 460))
        window.center()
        self.window = window
    }

    func show() {
        // `activate()` (macOS 14+) rather than the deprecated
        // `activate(ignoringOtherApps:)`.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
