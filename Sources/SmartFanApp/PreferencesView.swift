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
            if appState.daemonUnreachable {
                DaemonDownBanner(onRestart: { appState.restartDaemon() })
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

            if appState.activeProfile.id == FanProfile.fixed.id {
                rpmSlider
            }

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

    private var rpmRange: ClosedRange<Double> {
        guard let fan = appState.latestStatus?.fans.first, fan.maxRPM >= fan.minRPM else {
            return 0...0
        }
        return Double(fan.minRPM)...Double(fan.maxRPM)
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

            // The metric applies to the numbers and to the temperature curve.
            PickerRow(language.text("Temperature Metric"), selection: config.temperatureMetric) {
                Text(language.text("Average")).tag(TemperatureMetric.average)
                Text(language.text("Feels-like")).tag(TemperatureMetric.feelsLike)
            }

            Divider()
            PickerRow(language.text("Units"), selection: config.unitDisplay) {
                Text(language.text("None")).tag(UnitDisplay.none)
                Text(language.text("Compact")).tag(UnitDisplay.compact)
                Text(language.text("Full")).tag(UnitDisplay.full)
            }

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
        let readings = MenuBarContent.readings(appState.displayConfig, status: appState.latestStatus,
                                               fahrenheit: appState.useFahrenheit)
        Image(nsImage: MenuBarLabelImage.make(
            symbol: MenuBarLabel.symbol(for: appState.monitorState),
            temperature: readings.temperature, rpm: readings.rpm,
            needsWarning: false, colorScheme: colorScheme))
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

            Button {
                appState.checkForUpdatesNow()
            } label: {
                Label(language.text(appState.updateCheckInProgress ? "Checking…" : "Check for Updates"),
                      systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(appState.updateCheckInProgress)

            Divider()

            Link(language.text("Homepage"), destination: URL(string: "https://github.com/witt/smart-fan")!)
            Link(language.text("License"), destination: URL(string: "https://github.com/witt/smart-fan/blob/main/LICENSE")!)
            Link(language.text("Third-party notices"), destination: URL(string: "https://github.com/witt/smart-fan/blob/main/NOTICE.md")!)
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
