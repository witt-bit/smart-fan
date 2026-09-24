//
//  PreferencesView.swift
//  SmartFan
//
//  The preferences window: left vertical tabs (Fans / General / Menu Bar / About)
//  and a right content pane. The menu bar dropdown was retired in favour of this
//  window (see docs/menu-bar-display-plan.md §8).
//

import SwiftUI
import SmartFanCore
import SmartFanLocalization

enum PreferencesTab: String, CaseIterable, Identifiable {
    case fans, general, menuBar, about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .fans: return "Fans"
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .fans: return "fan"
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .about: return "info.circle"
        }
    }
}

/// Tab selection kept in an `ObservableObject` rather than `@State`: SwiftUI's
/// `@State` is a macro (`SwiftUIMacros`) that a CommandLineTools-only toolchain
/// cannot load, so this project avoids SwiftUI macros to stay buildable there.
@MainActor
final class PreferencesSelection: ObservableObject {
    @Published var tab: PreferencesTab = .fans
}

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore
    @StateObject private var selection = PreferencesSelection()

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection.tab) {
                ForEach(PreferencesTab.allCases) { item in
                    Label(language.text(item.titleKey), systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 150)

            Divider()

            ScrollView {
                Group {
                    switch selection.tab {
                    case .fans: FansPreferences()
                    case .general: GeneralPreferences()
                    case .menuBar: MenuBarPreferences()
                    case .about: AboutPreferences()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 640, height: 460)
    }
}

// MARK: - Fans

/// Live readings and quick mode controls. The alert strip and the full banner
/// migration land in MB-1.3; this keeps the app usable in the meantime.
private struct FansPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.daemonUnreachable {
                Label(language.text("Fan control unavailable"), systemImage: "exclamationmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                Text(language.text("The background service isn't responding, so profiles and Default can't change the fans right now."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(language.text("Restart daemon")) { appState.restartDaemon() }
            }

            Text(language.text("Current Mode")).font(.headline)
            Picker(language.text("Profile"), selection: Binding(
                get: { appState.activeProfile.id },
                set: { id in
                    if let profile = selectableProfiles.first(where: { $0.id == id }) {
                        appState.selectProfile(profile)
                    }
                }
            )) {
                ForEach(selectableProfiles) { profile in
                    Text(language.text(profile.name)).tag(profile.id)
                }
            }
            .labelsHidden()

            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { appState.activeProfile.id == "smart" },
                    set: { $0 ? appState.setSmart() : appState.resetAuto() }
                )) {
                    Label(language.text("Smart"), systemImage: "fan.fill")
                }
                .toggleStyle(.button)
                .tint(.orange)

                Button { appState.resetAuto() } label: {
                    Label(language.text("Default"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            if let status = appState.latestStatus {
                LabeledValue(language.text("Fans"), value: fanSummary(status))
                LabeledValue(language.text("CPU"), value: temp(prefixes: ["TC", "Tp"], status: status))
                LabeledValue(language.text("GPU"), value: temp(prefixes: ["TG", "Tg"], status: status))
                LabeledValue(language.text("RAM"), value: temp(prefixes: ["TR", "Tm", "TM"], status: status))
                LabeledValue(language.text("SSD"), value: temp(prefixes: ["TH"], status: status))
                LabeledValue(language.text("Ambient"), value: temp(prefixes: ["TA"], status: status))
                LabeledValue(language.text("Average"), value: format(status.averageTemp))
                LabeledValue(language.text("Feels-like"), value: format(status.batteryTemp))
            } else {
                Text(language.text("Reading sensors...")).foregroundStyle(.secondary)
            }
        }
    }

    private var selectableProfiles: [FanProfile] {
        [FanProfile.smart] + FanProfile.builtIn
    }

    private func fanSummary(_ status: ThermalStatus) -> String {
        guard let rpm = status.fanRPM else { return "—" }
        return "\(Int(rpm)) RPM"
    }

    private func temp(prefixes: [String], status: ThermalStatus) -> String {
        let peak = status.temperatures
            .filter { key, _ in prefixes.contains { key.hasPrefix($0) } }.values.max()
        return format(peak)
    }

    private func format(_ celsius: Float?) -> String {
        guard let celsius else { return "—" }
        let display = appState.useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.1f°%@", display, appState.useFahrenheit ? "F" : "C")
    }
}

// MARK: - General

private struct GeneralPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("General")).font(.headline)

            HStack {
                Text(language.text("Language"))
                Spacer()
                Picker(language.text("Language"), selection: Binding(
                    get: { language.selection }, set: { language.select($0) }
                )) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(language.title(for: choice)).tag(choice)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Toggle(language.text("°F / °C"), isOn: $appState.useFahrenheit)
            Toggle(language.text("Launch at Login"), isOn: $appState.launchAtLogin)
        }
    }
}

// MARK: - Menu Bar

private struct MenuBarPreferences: View {
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Menu Bar")).font(.headline)
            Text("MB-2.4 / MB-3.3").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - About

private struct AboutPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("About")).font(.headline)
            LabeledValue(language.text("Version"), value: SmartFanVersion.current)
            if let update = appState.availableUpdate {
                LabeledValue(language.text("Update available"), value: update.version)
            }
        }
    }
}

// MARK: - Shared

private struct LabeledValue: View {
    let label: String
    let value: String

    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
        }
    }
}
