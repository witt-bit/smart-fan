//
//  SmartFanApp.swift
//  SmartFan
//
//  AppKit lifecycle: a custom NSStatusItem (left click opens preferences, right
//  click shows the context menu) plus a preferences window. MenuBarExtra cannot
//  split a left click from a right click, so the app owns its status item directly
//  (see docs/menu-bar-display-plan.md §6).
//

import AppKit
import SmartFanCore
import SmartFanLocalization

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let language = AppLanguageStore()
    private var statusItem: StatusItemController?
    private var preferences: PreferencesWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon — menu bar only. Prevent duplicate instances.
        let bundleID = Bundle.main.bundleIdentifier ?? "org.witt.smartfan.app"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            TFLogger.shared.error("Another instance already running — quitting")
            NSApp.terminate(nil)
            return
        }

        let statusItem = StatusItemController(appState: appState, language: language)
        statusItem.onLeftClick = { [weak self] in self?.showPreferences() }
        statusItem.onRightClick = { [weak self] in self?.showContextMenu() }
        self.statusItem = statusItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reset fans on quit so the daemon doesn't hold stale APP settings — but
        // ONLY if the app owns the hold. A CLI hold (`sudo smart-fan max`) is the
        // user's deliberate, unsupervised choice; quitting the menu bar app must not
        // destroy it. Synchronous on purpose: the process is exiting, so an async
        // write would be dropped; both calls are bounded by the sendRaw timeout.
        let client = DaemonClient()
        if let state = try? client.readState(), state.owner == "app" {
            _ = try? client.execute(.resetAuto)
        }
        // owner == "cli" → leave the CLI hold alone; owner == "none" → nothing to reset.
    }

    // MARK: - Preferences

    private func showPreferences() {
        if preferences == nil {
            preferences = PreferencesWindowController(appState: appState, language: language)
        }
        preferences?.show()
    }

    @objc private func openPreferencesAction() { showPreferences() }

    // MARK: - Right-click menu

    private func showContextMenu() {
        let menu = NSMenu()

        let prefs = NSMenuItem(title: language.text("Preferences…"),
                               action: #selector(openPreferencesAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let profileItem = NSMenuItem(title: language.text("Profile"), action: nil, keyEquivalent: "")
        profileItem.submenu = profileMenu()
        menu.addItem(profileItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: language.text("Quit"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.showMenu(menu)
    }

    /// Every mode (Smart plus the built-ins), with the active one checked. All of
    /// them are switchable from here (docs/menu-bar-display-plan.md Q11.6).
    private func profileMenu() -> NSMenu {
        let menu = NSMenu()
        let active = appState.activeProfile.id
        for profile in [FanProfile.smart] + FanProfile.builtIn {
            let item = NSMenuItem(title: language.text(profile.name),
                                  action: #selector(selectProfileAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == active ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectProfileAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if id == FanProfile.smart.id {
            appState.setSmart()
        } else if let profile = FanProfile.builtIn.first(where: { $0.id == id }) {
            appState.selectProfile(profile)
        }
    }
}
