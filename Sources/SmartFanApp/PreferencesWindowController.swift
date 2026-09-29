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
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let appState: AppState

    init(appState: AppState, language: AppLanguageStore) {
        self.appState = appState
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
        super.init()
        window.delegate = self
    }

    func show() {
        // `activate()` (macOS 14+) rather than the deprecated
        // `activate(ignoringOtherApps:)`.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A check result belongs to the viewing that produced it. Closing the window
    /// clears it, so reopening never shows a stale answer — the window is hidden, not
    /// destroyed, so it would otherwise still be on screen.
    func windowWillClose(_ notification: Notification) {
        appState.clearManualUpdateResult()
    }
}
