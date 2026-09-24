//
//  StatusItemController.swift
//  SmartFan
//
//  Owns the NSStatusItem: renders the label image and routes left/right clicks.
//  MenuBarExtra cannot tell a left click from a right click, so the app manages
//  the status item directly (see docs/menu-bar-display-plan.md §6).
//

import AppKit
import Combine
import SwiftUI
import SmartFanCore
import SmartFanLocalization

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private let language: AppLanguageStore
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?

    /// Left click — open the preferences window.
    var onLeftClick: (() -> Void)?
    /// Right click — show the context menu.
    var onRightClick: (() -> Void)?

    init(appState: AppState, language: AppLanguageStore) {
        self.appState = appState
        self.language = language
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        // Repaint when any label-relevant value changes. These publishers fire AFTER
        // the value is set, so refresh() reads the new state (objectWillChange would
        // fire before it).
        Publishers.CombineLatest4(
            appState.$monitorState, appState.$maxTemp, appState.$useFahrenheit, appState.$daemonVersionMismatch
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        .store(in: &cancellables)

        appState.$daemonUnreachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &cancellables)

        // Redraw for the menu bar's light/dark appearance (the warning badge is
        // non-template and must pick its foreground per appearance). KVO on the
        // button's effectiveAppearance — AppKit posts no notification for this.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }

        refresh()
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    /// Pop `menu` at the item, then clear it so a later left click opens the
    /// preferences window instead of re-showing the menu.
    func showMenu(_ menu: NSMenu) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Rendering

    private func refresh() {
        guard let button = statusItem.button else { return }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme: ColorScheme = isDark ? .dark : .light

        let symbol = MenuBarLabel.symbol(for: appState.monitorState)
        let text = MenuBarLabel.temperatureText(appState.maxTemp, fahrenheit: appState.useFahrenheit)
        let needsWarning = appState.daemonVersionMismatch != nil || appState.daemonUnreachable

        button.image = MenuBarLabelImage.make(symbol: symbol, text: text,
                                             needsWarning: needsWarning, colorScheme: scheme)
        let reading = text.map { $0 + (appState.useFahrenheit ? "F" : "C") }
            ?? language.text("Temperature unavailable")
        button.toolTip = language.text("SmartFan: {reading}", ["reading": reading])
    }
}
