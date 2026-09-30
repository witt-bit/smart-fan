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
struct FansPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Alerts, in priority order: fan control is impossible without the daemon;
            // a terminal hold means the app is intentionally not controlling.
            if appState.daemonUnreachable {
                DaemonDownBanner(syncState: appState.daemonSyncState,
                                 onRestart: { appState.syncBackgroundService() })
            }
            if let hold = appState.externalHold {
                ExternalHoldBanner(hold: hold)
            }

            Text(language.text("Current Mode")).font(.headline)
            Picker(language.text("Profile"), selection: Binding(
                get: { appState.activeProfile.id },
                set: { id in
                    // Smart and Fixed Rate have their own entry points (Smart sets up its
                    // monitor state; Fixed re-applies its RPM), so route them explicitly.
                    if id == FanProfile.smart.id {
                        appState.setSmart()
                    } else if id == FanProfile.fixed.id {
                        appState.setFixedRPM(appState.fixedRPM)
                    } else if let profile = FanProfile.uiProfiles.first(where: { $0.id == id }) {
                        appState.selectProfile(profile)
                    }
                }
            )) {
                ForEach(FanProfile.uiProfiles) { profile in
                    Text(language.text(profile.name)).tag(profile.id)
                }
            }
            .labelsHidden()

            if appState.modeSwitchWasRefused, let remaining = appState.modeSwitchCooldownRemaining {
                Text(language.text("Just switched modes — {seconds}s before switching again. Default is always available.",
                                   ["seconds": String(remaining)]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.activeProfile.id == FanProfile.fixed.id {
                rpmSlider
            }

            Divider()

            // Live state: the mode above is the user's choice; this is what the
            // monitor is actually doing (a safety override or idle shows up here).
            HStack(spacing: 6) {
                Text(language.text("Status")).foregroundStyle(.secondary)
                Spacer()
                monitorStateLabel
            }

            Divider()

            if let status = appState.latestStatus {
                ForEach(status.fans, id: \.index) { fan in
                    LabeledValue(language.text("Fan {index}", ["index": String(fan.index)]),
                                 value: language.text("{rpm} RPM", ["rpm": String(fan.actualRPM)]))
                }
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

    /// Fixed Rate control: a slider across the fan's own range, in 100 RPM steps.
    /// Uses the range the hardware reports, so it can never ask for an unreachable
    /// speed (the daemon clamps as a backstop).
    @ViewBuilder
    private var rpmSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(language.text("Fan speed")).foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.fixedRPM) RPM").font(.system(.body, design: .monospaced))
            }
            Slider(value: Binding(
                get: { Double(appState.fixedRPM) },
                set: { appState.setFixedRPM(Int($0)) }
            ), in: rpmRange, step: 100)
            .disabled(rpmRange.lowerBound >= rpmRange.upperBound)
        }
    }

    /// The fan's own range when the hardware reports one. Falls back to a plausible
    /// range otherwise (some machines report no min/max), so the control still works;
    /// the daemon clamps whatever we send.
    private var rpmRange: ClosedRange<Double> {
        let range = FanProfile.fixedRPMRange(fan: appState.latestStatus?.fans.first)
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    @ViewBuilder
    private var monitorStateLabel: some View {
        switch appState.monitorState {
        case .safetyOverride:
            Label(language.text("SAFETY"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .active(let name):
            Label(language.text(name), systemImage: "fan.fill")
                .foregroundStyle(.orange)
        case .idle:
            // The monitor is not driving the fans — say who is. "Idle" next to a spinning
            // fan reading reads as "the fan is idle", when it only meant this app is not
            // the one setting the speed. Fixed Rate is the one case where the app still
            // holds the fans even though the monitor's tick does nothing.
            if appState.activeProfile.id == FanProfile.fixed.id {
                Label(language.text("Fixed Rate"), systemImage: "fan.fill")
                    .foregroundStyle(.orange)
            } else {
                Label(language.text("Apple auto"), systemImage: "fan")
                    .foregroundStyle(.secondary)
            }
        }
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

struct GeneralPreferences: View {
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

struct MenuBarPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    private var config: Binding<MenuBarDisplayConfig> { $appState.displayConfig }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("Menu Bar Style")).font(.headline)

            Picker("", selection: config.style) {
                Text(language.text("Icon + Numbers")).tag(MenuBarStyle.numbers)
                Text(language.text("Temperature Curve")).tag(MenuBarStyle.temperatureCurve)
                Text(language.text("RPM Curve")).tag(MenuBarStyle.rpmCurve)
                Text(language.text("Dual Curve")).tag(MenuBarStyle.dualCurve)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                Text(language.text("Preview")).foregroundStyle(.secondary)
                MenuBarPreview()
            }
            .padding(.vertical, 2)

            if appState.displayConfig.style == .numbers {
                Divider()
                // Both may be off: an icon-only item is a valid choice.
                Toggle(language.text("Show Temperature"), isOn: config.showTemperature)
                Toggle(language.text("Show RPM"), isOn: config.showRPM)
            }

            // The metric applies to the numbers and to the temperature curve, so it is
            // live only when a temperature is actually shown.
            PickerRow(language.text("Temperature Metric"), selection: config.temperatureMetric) {
                Text(language.text("Average")).tag(TemperatureMetric.average)
                Text(language.text("Feels-like")).tag(TemperatureMetric.feelsLike)
            }
            .disabled(!appState.displayConfig.temperatureMetricApplies)

            Divider()
            PickerRow(language.text("Units"), selection: config.unitDisplay) {
                Text(language.text("None")).tag(UnitDisplay.none)
                Text(language.text("Compact")).tag(UnitDisplay.compact)
                Text(language.text("Full")).tag(UnitDisplay.full)
            }
            .disabled(!appState.displayConfig.unitDisplayApplies)

            // Curve sampling settings only matter for the curve styles.
            if appState.displayConfig.style != .numbers {
                PickerRow(language.text("Sample Interval"), selection: config.sampleInterval) {
                    ForEach(MenuBarDisplayConfig.sampleIntervals, id: \.self) { value in
                        Text(MenuBarContent.durationLabel(value)).tag(value)
                    }
                }
                PickerRow(language.text("Time Window"), selection: config.window) {
                    ForEach(MenuBarDisplayConfig.windows, id: \.self) { value in
                        Text(MenuBarContent.durationLabel(value)).tag(value)
                    }
                }
            }
        }
    }
}

/// Renders the real status-item image, so the preview cannot drift from what the
/// menu bar actually shows.
private struct MenuBarPreview: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: MenuBarContent.image(
            config: appState.displayConfig,
            history: appState.menuBarHistory,
            monitorState: appState.monitorState,
            status: appState.latestStatus,
            fahrenheit: appState.useFahrenheit,
            needsWarning: false,
            colorScheme: colorScheme,
            statusBarThickness: NSStatusBar.system.thickness))
        .frame(height: NSStatusBar.system.thickness)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.18)))
    }
}

/// A label on the left, a compact pop-up on the right.
private struct PickerRow<Value: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: Value
    @ViewBuilder var content: () -> Content

    init(_ label: String, selection: Binding<Value>, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self._selection = selection
        self.content = content
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: $selection) { content() }
                .labelsHidden()
                .fixedSize()
        }
    }
}

// MARK: - About

struct AboutPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("About")).font(.headline)

            // Both update banners live here (decided in the plan): the About page
            // is where a user goes to find out about versions.
            if let daemonVersion = appState.daemonVersionMismatch {
                DaemonUpdateBanner(daemonVersion: daemonVersion)
            }
            if let update = appState.availableUpdate {
                UpdateAvailableBanner(update: update, onDismiss: { appState.dismissUpdate() })
            }

            LabeledValue(language.text("Version"), value: SmartFanVersion.current)

            // The button and its result share one row, in the fonts of the row above.
            // A result too long for the space wraps and the row grows, so no text is
            // cut short. The result is cleared when the window closes (see
            // PreferencesWindowController), so reopening never shows a stale answer.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    appState.checkForUpdatesNow()
                } label: {
                    Label(language.text(appState.manualUpdateCheck == .checking ? "Checking…" : "Check for Updates"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appState.manualUpdateCheck == .checking)
                .fixedSize()   // the result wraps instead; the button keeps its width

                Spacer(minLength: 8)

                if let result = updateResultText {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Link(language.text("Homepage"), destination: URL(string: "https://github.com/witt-bit/smart-fan")!)
            Link(language.text("License"), destination: URL(string: "https://github.com/witt-bit/smart-fan/blob/main/LICENSE")!)
            Link(language.text("Third-party notices"), destination: URL(string: "https://github.com/witt-bit/smart-fan/blob/main/NOTICE.md")!)
        }
    }

    /// `nil` while there is nothing to report, so the row collapses to just the button.
    private var updateResultText: String? {
        switch appState.manualUpdateCheck {
        case .idle, .checking: return nil
        case .upToDate: return language.text("Up to date")
        case .failed: return language.text("Couldn't reach GitHub")
        case .available(let version): return language.text("{version} available", ["version": version])
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
