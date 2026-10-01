//
//  MenuBarDisplay.swift
//  SmartFan
//
//  User-configurable menu bar content: style, metrics, units and curve settings.
//  Persisted as JSON in UserDefaults (key `menuBarDisplay`).
//
//  See docs/menu-bar-display-plan.md §5 (frozen model) and §3 (metric terms).
//

import Foundation

/// What the menu bar item shows.
///
/// The three curve styles used to be separate cases. They are merged into `curve`, with
/// `showTemperature` / `showRPM` choosing which sparklines are drawn — the same two
/// switches that choose which numbers the icon style prints. The old names are kept so a
/// configuration saved before the merge still decodes; `normalized()` folds them.
public enum MenuBarStyle: String, Codable, Sendable {
    /// Icon plus the numbers that are switched on.
    case numbers
    /// Sparklines for the readings that are switched on.
    case curve
    /// Legacy: a temperature sparkline only.
    case temperatureCurve
    /// Legacy: an RPM sparkline only.
    case rpmCurve
    /// Legacy: both sparklines overlaid.
    case dualCurve

    /// What the preferences offer. The legacy cases are decode-only.
    public static let offered: [MenuBarStyle] = [.numbers, .curve]

    /// True when the style draws a sparkline (and therefore needs sample history).
    public var usesCurve: Bool { self != .numbers }
}

/// Which temperature the numbers and the temperature curve use.
public enum TemperatureMetric: String, Codable, CaseIterable, Sendable {
    /// Mean of every sensor (includes the battery).
    case average
    /// Battery temperature.
    case feelsLike
}

/// How much of a unit to print next to a number.
public enum UnitDisplay: String, Codable, CaseIterable, Sendable {
    /// `48` / `2318`
    case none
    /// `48°` / `2318`
    case compact
    /// `48°C` / `2318 RPM`
    case full
}

public struct MenuBarDisplayConfig: Codable, Equatable, Sendable {
    public var style: MenuBarStyle
    /// Numbers style: show the temperature (icon upper-right). Curve style: draw the
    /// temperature sparkline.
    public var showTemperature: Bool
    /// Numbers style: show the RPM (icon lower-right). Curve style: draw the RPM
    /// sparkline.
    public var showRPM: Bool
    public var temperatureMetric: TemperatureMetric
    public var unitDisplay: UnitDisplay
    /// Curve sampling interval in seconds (1/2/3/5/10).
    public var sampleInterval: TimeInterval
    /// Curve history window in seconds (10/30/60/180).
    public var window: TimeInterval

    public init(style: MenuBarStyle = .numbers,
                showTemperature: Bool = true,
                showRPM: Bool = false,
                temperatureMetric: TemperatureMetric = .average,
                unitDisplay: UnitDisplay = .compact,
                sampleInterval: TimeInterval = 1,
                window: TimeInterval = 60) {
        self.style = style
        self.showTemperature = showTemperature
        self.showRPM = showRPM
        self.temperatureMetric = temperatureMetric
        self.unitDisplay = unitDisplay
        self.sampleInterval = sampleInterval
        self.window = window
    }

    public static let `default` = MenuBarDisplayConfig()

    /// Allowed values (also what the preferences UI offers).
    public static let sampleIntervals: [TimeInterval] = [1, 2, 3, 5, 10]
    public static let windows: [TimeInterval] = [10, 30, 60, 180]

    /// True when the temperature metric actually affects what is shown — whenever a
    /// temperature is shown at all, in either style. The preferences disable the picker
    /// when this is false, so a control that cannot change anything is not left live.
    public var temperatureMetricApplies: Bool { showTemperature }

    /// True when the unit suffix actually appears: the numbers style with at least
    /// one number shown. Curve styles draw no text, so the unit is inert there.
    public var unitDisplayApplies: Bool {
        style == .numbers && (showTemperature || showRPM)
    }

    /// True when the sampling interval and window change what is drawn: the curve style
    /// with at least one sparkline switched on.
    public var curveSettingsApply: Bool {
        style.usesCurve && (showTemperature || showRPM)
    }

    /// Clamp out-of-range values back to the allowed set. Applied to decoded input
    /// so a hand-edited plist can't put the renderer into a 0-second or 1-point state.
    /// Both numbers may be off — an icon-only item is a valid choice.
    public func normalized() -> MenuBarDisplayConfig {
        var copy = self
        // A configuration saved before the curve styles were merged still says which
        // curve it wanted; fold that into the single style plus the two switches, so an
        // existing user keeps seeing exactly what they saw.
        switch copy.style {
        case .temperatureCurve:
            copy.style = .curve
            copy.showTemperature = true
            copy.showRPM = false
        case .rpmCurve:
            copy.style = .curve
            copy.showTemperature = false
            copy.showRPM = true
        case .dualCurve:
            copy.style = .curve
            copy.showTemperature = true
            copy.showRPM = true
        case .numbers, .curve:
            break
        }
        if !Self.sampleIntervals.contains(copy.sampleInterval) { copy.sampleInterval = 1 }
        if !Self.windows.contains(copy.window) { copy.window = 60 }
        return copy
    }
}

// MARK: - Persistence

extension MenuBarDisplayConfig {
    public static let defaultsKey = "menuBarDisplay"

    /// Load from UserDefaults, falling back to the default config on missing or
    /// corrupt data (a bad value must never leave the menu bar unrenderable).
    public static func load(from defaults: UserDefaults = .standard) -> MenuBarDisplayConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(MenuBarDisplayConfig.self, from: data)
        else { return .default }
        return config.normalized()
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
