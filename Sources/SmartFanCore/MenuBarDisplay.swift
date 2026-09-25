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
public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    /// Icon plus temperature / RPM numbers.
    case numbers
    /// A small temperature sparkline.
    case temperatureCurve
    /// A small RPM sparkline.
    case rpmCurve
    /// Both curves overlaid in one small canvas.
    case dualCurve

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
    /// numbers style: show the temperature (icon upper-right).
    public var showTemperature: Bool
    /// numbers style: show the RPM (icon lower-right).
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

    /// Clamp out-of-range values back to the allowed set. Applied to decoded input
    /// so a hand-edited plist can't put the renderer into a 0-second or 1-point state.
    /// Both numbers may be off — an icon-only item is a valid choice.
    public func normalized() -> MenuBarDisplayConfig {
        var copy = self
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
