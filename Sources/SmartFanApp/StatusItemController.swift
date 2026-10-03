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
    /// Guards against `performClick` re-entering the click handler while the menu is
    /// being shown. The menu/`performClick` pairing is the canonical way to give a
    /// status item a context menu, but it must never recurse.
    private var isShowingMenu = false
    /// The light/dark scheme the current image was drawn for, so an appearance notification
    /// that changes nothing cannot start another repaint (see the KVO below).
    private var renderedScheme: ColorScheme?

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
            appState.$monitorState, appState.$latestStatus, appState.$useFahrenheit, appState.$daemonVersionMismatch
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        .store(in: &cancellables)

        appState.$daemonUnreachable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &cancellables)

        appState.$displayConfig
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &cancellables)

        // Curve styles redraw as samples arrive.
        appState.$menuBarHistory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &cancellables)

        // Redraw for the menu bar's light/dark appearance (the warning badge is
        // non-template and must pick its foreground per appearance). KVO on the
        // button's effectiveAppearance — AppKit posts no notification for this.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                // Only repaint when the *answer* changed. Assigning the image is itself enough
                // to make AppKit re-resolve the button's appearance, so refreshing on every
                // notification fed itself: measured, one refresh became ~4,900 a second, and
                // that was the whole of a "SmartFan uses a lot of CPU" report. The
                // NSAppearance instance changes far more often than the light/dark answer does.
                guard let self, self.needsRepaintForAppearance else { return }
                self.refresh()
            }
        }

        refresh()
    }

    @objc private func handleClick() {
        guard !isShowingMenu else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    /// Pop `menu` at the item, then clear it so a later left click opens the
    /// preferences window instead of re-showing the menu.
    func showMenu(_ menu: NSMenu) {
        guard !isShowingMenu, let button = statusItem.button else { return }
        isShowingMenu = true
        defer {
            isShowingMenu = false
            statusItem.menu = nil
            // Assigning `statusItem.menu` makes AppKit treat a click as "show the menu"
            // rather than sending the button's action. Clearing it is meant to restore the
            // action; re-asserting it is cheap and removes the doubt.
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem.menu = menu
        button.performClick(nil)
    }

    // MARK: - Rendering

    /// Whether the button's resolved scheme differs from the one the current image was drawn
    /// for. False for an appearance notification that changes nothing — the common case, and
    /// the one that must not trigger a repaint.
    private var needsRepaintForAppearance: Bool {
        guard let button = statusItem.button else { return false }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return (isDark ? ColorScheme.dark : .light) != renderedScheme
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme: ColorScheme = isDark ? .dark : .light
        renderedScheme = scheme

        let config = appState.displayConfig
        let needsWarning = appState.daemonVersionMismatch != nil || appState.daemonUnreachable

        button.image = MenuBarContent.image(
            config: config,
            history: appState.menuBarHistory,
            monitorState: appState.monitorState,
            status: appState.latestStatus,
            fahrenheit: appState.useFahrenheit,
            needsWarning: needsWarning,
            colorScheme: scheme,
            statusBarThickness: button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness)

        // The old MenuBarExtra label carried an accessibility label/value; a bare
        // NSStatusItem has none unless it is set explicitly.
        let readings = MenuBarContent.readings(config, status: appState.latestStatus,
                                               fahrenheit: appState.useFahrenheit)
        let reading = [readings.temperature, readings.rpm].compactMap { $0 }.joined(separator: " · ")
        let spoken = reading.isEmpty ? language.text("Temperature unavailable") : reading
        button.toolTip = language.text("SmartFan: {reading}", ["reading": spoken])
        button.setAccessibilityLabel("SmartFan")
        button.setAccessibilityValue(spoken)
    }
}
