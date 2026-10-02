import AppKit
import SwiftUI
import Testing
@testable import SmartFanApp
@testable import SmartFanCore
import SmartFanLocalization

@Suite("Localized panels — offscreen, no services", .serialized)
@MainActor
struct LocalizedPanelTests {
    @Test("Preferences pages render in three languages across alert states")
    func panelLayouts() async throws {
        let name = "SmartFan.PanelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let language = AppLanguageStore(defaults: defaults, preferredLanguages: { ["en"] })
        let state = AppState(startServices: false)
        state.activeProfile = .smart
        state.monitorState = .active(profileName: "Smart")
        state.latestStatus = ThermalStatus(fans: [
            .init(index: 0, actualRPM: 5777, targetRPM: 5777, minRPM: 1350, maxRPM: 5777, mode: "manual"),
            .init(index: 1, actualRPM: 5756, targetRPM: 5777, minRPM: 1350, maxRPM: 5777, mode: "manual"),
        ], temperatures: ["TCMb": 100, "Tg05": 73.7, "TRDX": 43.4, "TH0x": 26.3, "TAOL": 24.4],
           averageTemp: 60, batteryTemp: 31, fanRPM: 5766,
           // The sensors page needs all three states in one fixture: a key the app kept, one
           // it dropped with a reason, and keys this Mac does not publish.
           rawTemperatures: ["TCMb": 100, "Tp0W": 104.2, "Tg05": 73.7, "TRDX": 43.4,
                             "TH0x": 26.3, "TAOL": 24.4],
           sensorDrops: ["Tp0W": .belowDieFloor])

        // Every alert state is exercised: the Fans page carries the daemon-down
        // banner, the About page carries update-needed and update-available.
        state.daemonUnreachable = true
        state.daemonVersionMismatch = "0.2.3.5"
        state.availableUpdate = AvailableUpdate(version: "99.99.99",
                                                url: "https://github.com/witt-bit/smart-fan/releases")

        // The full window keeps its fixed size.
        let window = NSHostingView(rootView: PreferencesView()
            .environmentObject(state).environmentObject(language))
        window.setFrameSize(window.fittingSize)
        #expect(window.frame.width == 640)
        #expect(window.frame.height == 460)

        let pages: [AnyView] = [
            AnyView(FansPreferences()),
            AnyView(GeneralPreferences()),
            AnyView(MenuBarPreferences()),
            AnyView(SensorPreferences()),
            AnyView(AboutPreferences()),
        ]

        for choice in LocalizationCatalog.supportedLanguages {
            language.select(choice)
            try await Task.sleep(for: .milliseconds(30))
            for page in pages {
                let panel = NSHostingView(rootView: page
                    .environmentObject(state).environmentObject(language)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .light))
                panel.setFrameSize(panel.fittingSize)
                panel.layoutSubtreeIfNeeded()
                #expect(panel.frame.width > 0 && panel.frame.height > 0)
                let bitmap = try #require(panel.bitmapImageRepForCachingDisplay(in: panel.bounds))
                panel.cacheDisplay(in: panel.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(png.count > 500)
                if let directory = ProcessInfo.processInfo.environment["SMARTFAN_PREVIEW_DIR"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try png.write(to: url.appendingPathComponent("\(choice.rawValue).png"))
                }
            }
        }

        // Rendering must never mutate the state it reads.
        #expect(state.activeProfile == .smart)
        #expect(state.externalHold == nil)
        #expect(state.monitorState == .active(profileName: "Smart"))
    }
}
