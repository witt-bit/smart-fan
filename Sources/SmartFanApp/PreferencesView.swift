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
    case fans, general, menuBar, sensors, about

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .fans: return "Fans"
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .sensors: return "Sensors"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .fans: return "fan"
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        // Sensors sit beside About: they are the detail page you open when a reading looks
        // wrong, not part of everyday use.
        case .sensors: return "thermometer.medium"
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

    // Which controls a page shows, and whether they are live, follows one rule:
    //
    // - A control that **belongs to another style or mode** is **absent** — the unit
    //   picker is part of the numbers style, the sampling rows are part of the curve
    //   style, the Fixed Rate slider is part of Fixed Rate. Nothing there could ever
    //   take effect, so showing it greyed only adds noise.
    // - A control that belongs to what is selected but **cannot change anything right
    //   now** is **present and disabled**, never hidden — the metric needs a temperature
    //   on screen, "Also in Default mode" needs the protection above it, the sampling
    //   rows need a curve to sample for. A control that comes and goes reads as a bug; a
    //   greyed one reads as a reason.
    //
    // The two `…Applies` properties in `MenuBarDisplayConfig` are exactly the second
    // condition, so the views bind `.disabled()` to them rather than recomputing it.

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
                    case .sensors: SensorPreferences()
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
            // Who controls the fans comes first: it answers "what is going on right now",
            // and everything below either explains it or changes it.
            HStack(spacing: 6) {
                Text(language.text("Status")).foregroundStyle(.secondary)
                Spacer()
                monitorStateLabel
            }

            // The number the fan logic actually compares against, next to the status it
            // produces. Everything below is either the display side or a control; this is the
            // input the fan decisions are made from.
            LabeledValue(language.text("Control basis"), value: format(appState.controlBasisTemp),
                         hint: language.text("What the mode curves, the sustained window and the high-temperature ladder compare their thresholds against: the hottest key in the TC/Tp/TG/Tg groups. Those groups include keys that are not core temperatures, so it reads a few degrees above the CPU row — it is not the same quantity. The Sensors page lists which key is which."))
            if appState.protectionStage != .off {
                LabeledValue(language.text("Protection"),
                             value: language.text(appState.protectionStage == .fullSpeed ? "Full speed" : "Half speed"),
                             hint: language.text("Which step of the high-temperature protection ladder is holding the fans right now."))
            }

            Divider()

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

            // Two controllers on one fan is what makes these switches worth having: off
            // means the ladder never runs, and a hands-off mode is left to the system
            // unless the user asks otherwise (docs/high-temp-protection-plan.md).
            VStack(alignment: .leading, spacing: 4) {
                Toggle(language.text("High-temperature protection"),
                       isOn: $appState.highTempProtection)
                hint(language.text("Half fan speed above 90 °C for 10 s, full above 95 °C for 30 s."))
                // Always present, greyed while the feature above is off: a control that
                // comes and goes reads as a bug, a greyed one reads as a reason.
                Toggle(language.text("Also in Default mode"),
                       isOn: $appState.protectionInDefaultMode)
                    .padding(.leading, 16)
                    .disabled(!appState.highTempProtection)
                hint(language.text("Default leaves the fans to the system, so it is left alone."))
                    .padding(.leading, 16)
            }

            Divider()

            if let status = appState.latestStatus {
                Text(language.text("Reference readings"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The one place that can say it plainly: the menu bar number is a reading, not
                // the control basis, and no reading changes what the fans do.
                Text(language.text("The display side: the menu bar number is one of these. Nothing here changes what the fans do — the control basis above is what the fan logic uses."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(status.fans, id: \.index) { fan in
                    LabeledValue(language.text("Fan {index}", ["index": String(fan.index)]),
                                 value: language.text("Actual {actual} · target {target} RPM",
                                                      ["actual": String(fan.actualRPM),
                                                       "target": String(fan.targetRPM)]),
                                 hint: language.text("Actual is the fan's own counter (F{index}Ac). Target is what it was last told (F{index}Tg): the mode's target, the current step of a ramp, or the system's own value while a hands-off mode is selected — so the two differing means a write is in flight, or failed and is being retried."))
                }
                // CPU and GPU use the panel's own definitions in Core, not a raw prefix
                // sweep: the `TC`/`Tp` groups also carry derived keys that read 10–13 °C
                // above the cores (`Tp0W` was the max in every sample here), and the menu
                // bar headline is computed from the same core reading. Measured before this
                // change the row sat 0.3–10.7 °C (usually 7–10) above the headline.
                // See docs/upstream-divergence.md and docs/thermal-sensor-calibration-20260924.md.
                //
                // The ⓘ on each row names the sensors behind the number and how they are
                // combined, so a reading that differs from another app can be traced
                // without reading the source.
                LabeledValue(language.text("CPU"), value: format(status.displayedCPUTemp),
                             hint: language.text("Hottest CPU core, from the core sensors calibrated for this chip — not the SoC hotspot keys, which read 10–13 °C higher."))
                LabeledValue(language.text("GPU"), value: format(status.displayedGPUTemp),
                             hint: language.text("Hottest GPU sensor (TG*, Tg*)."))
                LabeledValue(language.text("RAM"), value: temp(prefixes: ["TR", "Tm", "TM"], status: status),
                             hint: language.text("Hottest memory sensor (TRDX, Tm*, TMVR)."))
                LabeledValue(language.text("SSD"), value: temp(prefixes: ["TH"], status: status),
                             hint: language.text("Hottest SSD sensor (TH*)."))
                LabeledValue(language.text("Ambient"), value: temp(prefixes: ["TA"], status: status),
                             hint: language.text("Hottest ambient sensor (TAOL, TA0P)."))
                LabeledValue(language.text("Average"), value: format(status.averageTemp),
                             hint: language.text("Arithmetic mean of every readable sensor, the battery, ambient and SSD included."))
                LabeledValue(language.text("Feels-like"), value: format(status.batteryTemp),
                             hint: language.text("Battery temperature (TB0T/TB1T/TB2T and the IOHID battery keys); blank on Macs with no readable battery sensor."))
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

    /// Secondary line under a control: small, dim, and free to wrap.
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
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

            // "°F / °C" did not say what checking it did; the box means "show Fahrenheit"
            // in the menu bar and every temperature row.
            Toggle(language.text("Use °F"), isOn: $appState.useFahrenheit)
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
                Text(language.text("Curve")).tag(MenuBarStyle.curve)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                Text(language.text("Preview")).foregroundStyle(.secondary)
                MenuBarPreview()
            }
            .padding(.vertical, 2)

            Divider()

            // One pair of switches for both styles: the numbers style prints the readings
            // that are on, the curve style draws them. Both may be off — an icon-only item
            // is a valid choice — and everything below is live only while the reading it
            // belongs to is on.
            Toggle(language.text("Show Temperature"), isOn: config.showTemperature)
            Toggle(language.text("Show RPM"), isOn: config.showRPM)

            // The metric names the temperature, so it needs one on screen.
            PickerRow(language.text("Temperature Metric"), selection: config.temperatureMetric) {
                Text(language.text("Average")).tag(TemperatureMetric.average)
                Text(language.text("Feels-like")).tag(TemperatureMetric.feelsLike)
            }
            .disabled(!appState.displayConfig.temperatureMetricApplies)

            // Units suffix a number, so they belong to the numbers style: a curve draws no
            // text at all. The row is absent there rather than greyed, and is greyed in the
            // numbers style while both numbers are off — there is nothing to suffix.
            if appState.displayConfig.style == .numbers {
                Divider()
                PickerRow(language.text("Units"), selection: config.unitDisplay) {
                    Text(language.text("None")).tag(UnitDisplay.none)
                    Text(language.text("Compact")).tag(UnitDisplay.compact)
                    Text(language.text("Full")).tag(UnitDisplay.full)
                }
                .disabled(!appState.displayConfig.unitDisplayApplies)
            }

            // Sampling belongs to the curve style the same way. In the curve style the rows
            // stay put and grey out while both switches are off, since then there is no
            // sparkline to sample for.
            if appState.displayConfig.style.usesCurve {
                Divider()
                PickerRow(language.text("Sample Interval"), selection: config.sampleInterval) {
                    ForEach(MenuBarDisplayConfig.sampleIntervals, id: \.self) { value in
                        Text(MenuBarContent.durationLabel(value)).tag(value)
                    }
                }
                .disabled(!appState.displayConfig.curveSettingsApply)
                PickerRow(language.text("Time Window"), selection: config.window) {
                    ForEach(MenuBarDisplayConfig.windows, id: \.self) { value in
                        Text(MenuBarContent.durationLabel(value)).tag(value)
                    }
                }
                .disabled(!appState.displayConfig.curveSettingsApply)
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
        // Hug the image: the curve canvas already keeps 4pt blank either side (so it never
        // butts against the neighbouring menu bar icons), and 6pt more inside the box read
        // as a wide margin around a 48pt image.
        .padding(.horizontal, 2)
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

// MARK: - Sensors

/// Every key the app probes: the value the SMC returned, whether the app kept it and why
/// not, and what reads it.
///
/// The Fans page shows derived readings; this is the raw material they are derived from, and
/// the only place the fan logic's own basis is visible (docs/sensor-list-plan.md). Keys the
/// app *dropped* are listed too: a key that reads something and is not used has to be
/// visible with its reason, or the list looks like it is hiding readings — the difference
/// between this list and the CLI's full `discover` dump is exactly what needs explaining.
struct SensorPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = appState.latestStatus {
                let rows = status.sensorReadings()
                header(rows)
                Divider()
                // Lazy: 57 rows on this Mac, rebuilt with every status update, most off screen.
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups(rows), id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.text(heading(group.kind)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(group.rows, id: \.key) { SensorRow(reading: $0) }
                        }
                    }
                }
            } else {
                Text(language.text("Reading sensors...")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func header(_ rows: [SensorReading]) -> some View {
        let provided = rows.filter { $0.raw != nil }.count
        VStack(alignment: .leading, spacing: 2) {
            Text(language.text("{provided} of {total} keys on this Mac.",
                               ["provided": String(provided), "total": String(rows.count)]))
                .font(.caption)
                .foregroundStyle(.secondary)
            // Which classification is in force, so the list never implies more than it knows:
            // CPU keys are either per-chip calibrated or merely grouped by prefix.
            Text(ThermalStatus.validatedCoreKeys.isEmpty
                 ? language.text("No calibrated core table for this chip: the CPU keys are grouped by prefix.")
                 : language.text("CPU core keys come from this chip's calibrated table."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groups(_ rows: [SensorReading]) -> [(kind: SensorRole.Kind, rows: [SensorReading])] {
        SensorRole.Kind.allCases.compactMap { kind in
            let matching = rows.filter { $0.role.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    private func heading(_ kind: SensorRole.Kind) -> String {
        switch kind {
        case .cpuCore: return "CPU cores"
        case .cpuPrefix: return "CPU keys grouped by prefix (this chip has no table)"
        case .cpuDerived: return "CPU group keys that are not a core temperature"
        case .gpu: return "GPU"
        case .memory: return "RAM"
        case .ssd: return "SSD"
        case .ambient: return "Ambient"
        case .battery: return "Battery"
        case .power: return "Power delivery"
        case .other: return "Other"
        }
    }
}

/// One key: its reading, why the app did or did not use it, and who uses it.
private struct SensorRow: View {
    let reading: SensorReading
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(reading.key)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(reading.drop == nil ? .primary : .secondary)
                .frame(width: 78, alignment: .trailing)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// The value the app works with, or the raw one when it dropped the key: showing a
    /// dropped reading is the point of the list.
    private var value: String {
        if let accepted = reading.accepted { return temperature(accepted) }
        if let raw = reading.raw { return temperature(raw) }
        return "—"
    }

    private var note: String {
        switch reading.drop {
        case nil: return usedBy
        case .absent: return language.text("Not published on this Mac")
        case .outOfRange: return language.text("Outside 0–150 °C")
        case .batteryKey: return language.text("IOHID identifies it as a battery sensor")
        case .belowDieFloor: return language.text("A die key under 10 °C: a gated core's placeholder")
        }
    }

    private var usedBy: String {
        reading.role.uses.map { language.text(label($0)) }.joined(separator: " · ")
    }

    private func label(_ use: SensorRole.Use) -> String {
        switch use {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .ssd: return "SSD"
        case .ambient: return "Ambient"
        case .feelsLike: return "Feels-like"
        case .average: return "Average"
        case .control: return "Fan control"
        }
    }

    private func temperature(_ celsius: Float) -> String {
        let display = appState.useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return String(format: "%.1f°%@", display, appState.useFahrenheit ? "F" : "C")
    }
}

// MARK: - About

struct AboutPreferences: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var language: AppLanguageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // No page title: the sidebar already names the page, and repeating it only
            // pushed the content down. Same on the General page.

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
    /// Where the value comes from and how it is aggregated. nil hides the ⓘ.
    let hint: String?

    init(_ label: String, value: String, hint: String? = nil) {
        self.label = label
        self.value = value
        self.hint = hint
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced))
            HintButton(text: hint)
        }
    }
}

/// The ⓘ at the end of a reading. A popover rather than a tooltip: an explanation has to
/// survive the pointer moving in order to read it.
private struct HintButton: View {
    let text: String?
    @StateObject private var state = HintState()

    var body: some View {
        if let text {
            Button { state.shown.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $state.shown) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 280, alignment: .leading)
                    .padding(12)
            }
        } else {
            // Keep the column: a row without a hint still reserves the ⓘ's width, so the
            // values above and below it stay aligned.
            Image(systemName: "info.circle").font(.caption).opacity(0)
        }
    }
}

/// One per hint button: `@State` is a macro this toolchain cannot load (see
/// PreferencesSelection).
private final class HintState: ObservableObject {
    @Published var shown = false
}
