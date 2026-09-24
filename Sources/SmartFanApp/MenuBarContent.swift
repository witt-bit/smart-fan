//
//  MenuBarContent.swift
//  SmartFan
//
//  Turns a status + display config into the strings the menu bar draws. Unit
//  granularity and the °C/°F choice live here so the renderer only draws text.
//  See docs/menu-bar-display-plan.md §4 (V1/V4) and §3 (metrics).
//

import Foundation
import SmartFanCore

enum MenuBarContent {
    /// Integer temperature reading, or nil when unavailable/unrepresentable.
    /// Truncates toward zero, matching the shipped menu bar reading.
    static func temperature(_ celsius: Float?, fahrenheit: Bool, units: UnitDisplay) -> String? {
        guard let celsius else { return nil }
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        guard value.isFinite, let integer = Int(exactly: Double(value.rounded(.towardZero))) else { return nil }
        switch units {
        case .none: return "\(integer)"
        case .compact: return "\(integer)°"
        case .full: return "\(integer)°\(fahrenheit ? "F" : "C")"
        }
    }

    /// Integer RPM reading, or nil when unavailable.
    static func rpm(_ value: Float?, units: UnitDisplay) -> String? {
        guard let value, value.isFinite, let integer = Int(exactly: Double(value.rounded())) else { return nil }
        switch units {
        case .none, .compact: return "\(integer)"
        case .full: return "\(integer) RPM"
        }
    }

    /// The temperature the config's metric points at.
    static func metricValue(_ status: ThermalStatus?, _ metric: TemperatureMetric) -> Float? {
        guard let status else { return nil }
        switch metric {
        case .average: return status.averageTemp
        case .feelsLike: return status.batteryTemp
        }
    }

    /// Compact, language-neutral duration label for the curve pickers (`1s`, `3min`).
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return value >= 60 && value % 60 == 0 ? "\(value / 60)min" : "\(value)s"
    }

    /// Which readings the config wants shown. Curve styles fall back to the reading
    /// they will plot until the curve renderer lands (P3), so the style choice is
    /// visible rather than silently ignored.
    static func visibleReadings(_ config: MenuBarDisplayConfig) -> (temperature: Bool, rpm: Bool) {
        switch config.style {
        case .numbers: return (config.showTemperature, config.showRPM)
        case .temperatureCurve: return (true, false)
        case .rpmCurve: return (false, true)
        case .dualCurve: return (true, true)
        }
    }

    /// The menu bar's formatted strings, honouring the config's units and metric.
    /// Shared by the status item and the preferences preview so they cannot diverge.
    static func readings(_ config: MenuBarDisplayConfig, status: ThermalStatus?, fahrenheit: Bool)
        -> (temperature: String?, rpm: String?) {
        let visible = visibleReadings(config)
        let metric = metricValue(status, config.temperatureMetric)
        return (
            visible.temperature ? temperature(metric, fahrenheit: fahrenheit, units: config.unitDisplay) : nil,
            visible.rpm ? rpm(status?.fanRPM, units: config.unitDisplay) : nil
        )
    }
}
