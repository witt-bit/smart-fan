//
//  MenuBarContent.swift
//  SmartFan
//
//  Turns a status + display config into the strings the menu bar draws. Unit
//  granularity and the °C/°F choice live here so the renderer only draws text.
//  See docs/menu-bar-display-plan.md §4 (V1/V4) and §3 (metrics).
//

import AppKit
import Foundation
import SmartFanCore
import SwiftUI

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

    /// Which readings the style prints as numbers. Curve styles print none — they draw the
    /// readings the two switches select instead.
    static func visibleReadings(_ config: MenuBarDisplayConfig) -> (temperature: Bool, rpm: Bool) {
        guard config.style == .numbers else { return (false, false) }
        return (config.showTemperature, config.showRPM)
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

    /// Curve colours (plan §4 V3).
    static let temperatureCurveColor = NSColor.systemOrange
    static let rpmCurveColor = NSColor.systemTeal

    /// The curves the style asks for, oldest → newest: temperature first, then RPM, so a
    /// correlated pair still reads as two bands. Readings that were unreadable are left
    /// out rather than plotted as zero. Empty in the numbers style, and empty when both
    /// switches are off — which the renderer treats as an icon-only item.
    static func curves(_ config: MenuBarDisplayConfig, history: MenuBarHistory)
        -> [(values: [Float], color: NSColor)] {
        guard config.style.usesCurve else { return [] }
        var curves: [(values: [Float], color: NSColor)] = []
        if config.showTemperature {
            curves.append((history.samples.compactMap { $0.temperature }, temperatureCurveColor))
        }
        if config.showRPM {
            curves.append((history.samples.compactMap { $0.rpm }, rpmCurveColor))
        }
        return curves
    }

    /// The single image the menu bar item shows. Shared with the preferences preview
    /// so what the user sees there is exactly what the menu bar renders.
    static func image(config: MenuBarDisplayConfig,
                      history: MenuBarHistory,
                      monitorState: MonitorState,
                      status: ThermalStatus?,
                      fahrenheit: Bool,
                      needsWarning: Bool,
                      colorScheme: ColorScheme,
                      statusBarThickness: CGFloat) -> NSImage {
        let symbol = MenuBarLabelImage.make(symbol: MenuBarLabel.symbol(for: monitorState),
                                            temperature: nil, rpm: nil,
                                            needsWarning: needsWarning, colorScheme: colorScheme,
                                            statusBarThickness: statusBarThickness)
        guard config.style.usesCurve else {
            let reading = readings(config, status: status, fahrenheit: fahrenheit)
            return MenuBarLabelImage.make(symbol: MenuBarLabel.symbol(for: monitorState),
                                          temperature: reading.temperature, rpm: reading.rpm,
                                          needsWarning: needsWarning, colorScheme: colorScheme,
                                          statusBarThickness: statusBarThickness)
        }
        let drawn = curves(config, history: history)
        // Both switches off in the curve style is the icon-only item, the same choice the
        // numbers style offers.
        guard !drawn.isEmpty else { return symbol }
        return MenuBarLabelImage.makeCurve(curves: drawn,
                                           needsWarning: needsWarning,
                                           statusBarThickness: statusBarThickness)
    }
}
