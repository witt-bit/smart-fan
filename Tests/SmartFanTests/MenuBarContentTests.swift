import AppKit
import SwiftUI
import Testing
@testable import SmartFanApp
import SmartFanCore

@Suite("Menu bar content")
@MainActor
struct MenuBarContentTests {
    private func status(average: Float?, battery: Float?, rpm: Float?) -> ThermalStatus {
        ThermalStatus(fans: [], temperatures: [:],
                      averageTemp: average, batteryTemp: battery, fanRPM: rpm)
    }

    @Test("Temperature honours units, Fahrenheit and truncation")
    func temperature() {
        #expect(MenuBarContent.temperature(48.2, fahrenheit: false, units: .none) == "48")
        #expect(MenuBarContent.temperature(48.2, fahrenheit: false, units: .compact) == "48°")
        #expect(MenuBarContent.temperature(48.2, fahrenheit: false, units: .full) == "48°C")
        #expect(MenuBarContent.temperature(48, fahrenheit: true, units: .full) == "118°F")
        #expect(MenuBarContent.temperature(nil, fahrenheit: false, units: .compact) == nil)
        #expect(MenuBarContent.temperature(.nan, fahrenheit: false, units: .compact) == nil)
    }

    @Test("RPM shows a unit only at full granularity")
    func rpm() {
        #expect(MenuBarContent.rpm(2318.4, units: .none) == "2318")
        #expect(MenuBarContent.rpm(2318.4, units: .compact) == "2318")
        #expect(MenuBarContent.rpm(2318.4, units: .full) == "2318 RPM")
        #expect(MenuBarContent.rpm(nil, units: .full) == nil)
    }

    @Test("Readings follow the style and the temperature metric")
    func readings() {
        let s = status(average: 50, battery: 30, rpm: 2000)
        var config = MenuBarDisplayConfig.default
        config.showTemperature = true
        config.showRPM = true
        let both = MenuBarContent.readings(config, status: s, fahrenheit: false)
        #expect(both.temperature == "50°")
        #expect(both.rpm == "2000")

        config.temperatureMetric = .feelsLike
        #expect(MenuBarContent.readings(config, status: s, fahrenheit: false).temperature == "30°")

        // Curve styles fall back to the reading they will plot until P3.
        config.style = .rpmCurve
        let rpmOnly = MenuBarContent.readings(config, status: s, fahrenheit: false)
        #expect(rpmOnly.temperature == nil)
        #expect(rpmOnly.rpm == "2000")

        config.style = .temperatureCurve
        #expect(MenuBarContent.readings(config, status: s, fahrenheit: false).rpm == nil)
    }

    @Test("Duration labels are compact")
    func durations() {
        #expect(MenuBarContent.durationLabel(1) == "1s")
        #expect(MenuBarContent.durationLabel(10) == "10s")
        #expect(MenuBarContent.durationLabel(180) == "3min")
    }

    @Test("Two-line rendering draws the wider reading and stays within the width cap")
    func twoLineImage() {
        let image = MenuBarLabelImage.make(symbol: "fan", temperature: "48°", rpm: "2318",
                                           needsWarning: false, colorScheme: .light)
        #expect(image.isTemplate)
        #expect(image.size.width <= MenuBarLabelImage.maximumWidth + 2)
        #expect(image.size.height >= 20)
        // A single value still uses the one-line path.
        let single = MenuBarLabelImage.make(symbol: "fan", temperature: "48°", rpm: nil,
                                            needsWarning: false, colorScheme: .light)
        #expect(single.size.width > 0)
    }

    @Test("The two-line font fits the status bar and never exceeds the menu bar font")
    func twoLineFont() {
        for thickness in [22.0, 24.0, 33.0] as [CGFloat] {
            let font = MenuBarLabelImage.twoLineFont(statusBarThickness: thickness)
            let lineHeight = font.ascender - font.descender + font.leading
            #expect(2 * lineHeight <= max(thickness, 14) + 2)
            #expect(font.pointSize <= NSFont.menuBarFont(ofSize: 0).pointSize)
            #expect(font.pointSize >= 8)
        }
    }
}
