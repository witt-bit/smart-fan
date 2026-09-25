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

    @Test("Missing metrics degrade to nothing rather than zero")
    func missingMetricsDegrade() {
        // A machine that reports no sensors and no fan readings at all.
        let empty = status(average: nil, battery: nil, rpm: nil)
        var config = MenuBarDisplayConfig.default
        config.showTemperature = true
        config.showRPM = true
        let readings = MenuBarContent.readings(config, status: empty, fahrenheit: false)
        #expect(readings.temperature == nil)
        #expect(readings.rpm == nil)
        // …and the item still renders (icon only).
        let image = MenuBarContent.image(config: config, history: MenuBarHistory(), monitorState: .idle,
                                         status: empty, fahrenheit: false, needsWarning: false,
                                         colorScheme: .light, statusBarThickness: 22)
        #expect(image.size.width > 0)

        // A nil status degrades the same way.
        let none = MenuBarContent.readings(config, status: nil, fahrenheit: false)
        #expect(none.temperature == nil && none.rpm == nil)
    }

    @Test("A machine with no battery sensor reports no feels-like temperature")
    func noBatterySensors() {
        let noBattery = status(average: 48, battery: nil, rpm: 2000)
        var config = MenuBarDisplayConfig.default
        config.temperatureMetric = .feelsLike
        #expect(MenuBarContent.readings(config, status: noBattery, fahrenheit: false).temperature == nil)
        // The average metric still works on the same machine.
        config.temperatureMetric = .average
        #expect(MenuBarContent.readings(config, status: noBattery, fahrenheit: false).temperature == "48°")
    }

    // MARK: - Curves

    private func history(_ temps: [Float?], _ rpms: [Float?]) -> MenuBarHistory {
        var h = MenuBarHistory()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for (index, pair) in zip(temps, rpms).enumerated() {
            h.append(.init(time: base.addingTimeInterval(Double(index)),
                           temperature: pair.0, rpm: pair.1), interval: 1, window: 60)
        }
        return h
    }

    @Test("Curve inputs follow the style")
    func curveInputs() {
        let h = history([40, 50, 60], [1000, 2000, 3000])
        var config = MenuBarDisplayConfig.default

        config.style = .temperatureCurve
        var curves = MenuBarContent.curves(config, history: h)
        #expect(curves.count == 1)
        #expect(curves[0].values == [40, 50, 60])

        config.style = .rpmCurve
        curves = MenuBarContent.curves(config, history: h)
        #expect(curves.count == 1)
        #expect(curves[0].values == [1000, 2000, 3000])

        config.style = .dualCurve
        #expect(MenuBarContent.curves(config, history: h).count == 2)

        config.style = .numbers
        #expect(MenuBarContent.curves(config, history: h).isEmpty)
    }

    @Test("Unreadable samples are left out of a curve, not plotted as zero")
    func curveSkipsUnreadable() {
        let h = history([40, nil, 60], [nil, 2000, nil])
        var config = MenuBarDisplayConfig.default
        config.style = .temperatureCurve
        #expect(MenuBarContent.curves(config, history: h)[0].values == [40, 60])
        config.style = .rpmCurve
        #expect(MenuBarContent.curves(config, history: h)[0].values == [2000])
    }

    @Test("The curve canvas fills the bar, is coloured, and draws for thin data")
    func curveImage() {
        let empty = MenuBarLabelImage.makeCurve(curves: [(values: [], color: .systemOrange)],
                                                needsWarning: false, statusBarThickness: 22)
        #expect(!empty.isTemplate)   // coloured, so never a template
        #expect(empty.size.width == MenuBarLabelImage.curveWidth)
        #expect(empty.size.height == 22)
        #expect(empty.size.width <= MenuBarLabelImage.maximumWidth)

        // Zero, one and many points all render without trapping.
        for values: [Float] in [[], [50], [1, 2, 3, 4, 5, 6, 7, 8], [10, 10, 10]] {
            let image = MenuBarLabelImage.makeCurve(curves: [(values, .systemTeal)],
                                                    needsWarning: false, statusBarThickness: 24)
            #expect(image.size.width == MenuBarLabelImage.curveWidth)
            #expect(image.size.height == 24)
        }

        // A warning turns the whole curve item red, matching the icon. Both must render.
        for warning in [false, true] {
            let image = MenuBarLabelImage.makeCurve(curves: [(values: [1, 2], color: .systemOrange),
                                                             (values: [9, 8], color: .systemTeal)],
                                                    needsWarning: warning, statusBarThickness: 24)
            #expect(!image.isTemplate)
        }
    }
}
