import Foundation
import Testing
@testable import SmartFanCore

@Suite("Menu bar display config")
struct MenuBarDisplayConfigTests {
    private func freshDefaults() -> UserDefaults {
        let name = "smartfan.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Defaults match the frozen spec")
    func defaults() {
        let c = MenuBarDisplayConfig.default
        #expect(c.style == .numbers)
        #expect(c.showTemperature == true)
        #expect(c.showRPM == false)
        #expect(c.temperatureMetric == .average)
        #expect(c.unitDisplay == .compact)
        #expect(c.sampleInterval == 1)
        #expect(c.window == 60)
    }

    @Test("Round-trips through UserDefaults")
    func roundTrip() {
        let defaults = freshDefaults()
        var c = MenuBarDisplayConfig.default
        c.style = .dualCurve
        c.showRPM = true
        c.temperatureMetric = .feelsLike
        c.unitDisplay = .full
        c.sampleInterval = 5
        c.window = 180
        c.save(to: defaults)
        #expect(MenuBarDisplayConfig.load(from: defaults) == c)
    }

    @Test("Missing and corrupt data fall back to the default")
    func fallback() {
        let defaults = freshDefaults()
        #expect(MenuBarDisplayConfig.load(from: defaults) == .default)
        defaults.set(Data("not json".utf8), forKey: MenuBarDisplayConfig.defaultsKey)
        #expect(MenuBarDisplayConfig.load(from: defaults) == .default)
    }

    @Test("Out-of-range values are clamped to the allowed sets")
    func normalization() {
        let bad = MenuBarDisplayConfig(sampleInterval: 7, window: 999)
        let n = bad.normalized()
        #expect(n.sampleInterval == 1)
        #expect(n.window == 60)
        let defaults = freshDefaults()
        bad.save(to: defaults)
        #expect(MenuBarDisplayConfig.load(from: defaults).sampleInterval == 1)
        #expect(MenuBarDisplayConfig.load(from: defaults).window == 60)
    }

    @Test("Only the number style skips curves")
    func usesCurve() {
        #expect(MenuBarStyle.numbers.usesCurve == false)
        for style in [MenuBarStyle.temperatureCurve, .rpmCurve, .dualCurve] {
            #expect(style.usesCurve)
        }
    }

    @Test("The temperature metric is live only when a temperature is shown")
    func temperatureMetricApplies() {
        // Numbers: follows the temperature toggle.
        #expect(MenuBarDisplayConfig(style: .numbers, showTemperature: true).temperatureMetricApplies)
        #expect(!MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: true).temperatureMetricApplies)
        #expect(!MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: false).temperatureMetricApplies)
        // Curves: only the ones that draw a temperature.
        #expect(MenuBarDisplayConfig(style: .temperatureCurve).temperatureMetricApplies)
        #expect(MenuBarDisplayConfig(style: .dualCurve).temperatureMetricApplies)
        #expect(!MenuBarDisplayConfig(style: .rpmCurve).temperatureMetricApplies)
    }

    @Test("The unit suffix is live only when a number is drawn")
    func unitDisplayApplies() {
        #expect(MenuBarDisplayConfig(style: .numbers, showTemperature: true).unitDisplayApplies)
        #expect(MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: true).unitDisplayApplies)
        #expect(!MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: false).unitDisplayApplies)
        for style in [MenuBarStyle.temperatureCurve, .rpmCurve, .dualCurve] {
            #expect(!MenuBarDisplayConfig(style: style).unitDisplayApplies)
        }
    }

    @Test("Both numbers may be off (an icon-only item is a valid choice)")
    func bothNumbersMayBeOff() {
        let off = MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: false)
        #expect(off.normalized() == off)
        let defaults = freshDefaults()
        off.save(to: defaults)
        #expect(MenuBarDisplayConfig.load(from: defaults).showTemperature == false)
        #expect(MenuBarDisplayConfig.load(from: defaults).showRPM == false)
    }
}
