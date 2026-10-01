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
        c.style = .curve
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
        #expect(MenuBarStyle.curve.usesCurve)
        // The legacy names still read as curve styles, in case one is decoded.
        for style in [MenuBarStyle.temperatureCurve, .rpmCurve, .dualCurve] {
            #expect(style.usesCurve)
        }
        // And only the two current styles are offered.
        #expect(MenuBarStyle.offered == [.numbers, .curve])
    }

    @Test("A configuration saved before the curve styles were merged still shows the same thing")
    func legacyStylesMigrate() {
        #expect(MenuBarDisplayConfig(style: .temperatureCurve).normalized()
                == MenuBarDisplayConfig(style: .curve, showTemperature: true, showRPM: false))
        #expect(MenuBarDisplayConfig(style: .rpmCurve).normalized()
                == MenuBarDisplayConfig(style: .curve, showTemperature: false, showRPM: true))
        #expect(MenuBarDisplayConfig(style: .dualCurve).normalized()
                == MenuBarDisplayConfig(style: .curve, showTemperature: true, showRPM: true))

        // Through the store, which is where a saved value actually gets migrated.
        let defaults = freshDefaults()
        let legacy = #"{"style":"dualCurve","showTemperature":true,"showRPM":true,"temperatureMetric":"average","unitDisplay":"compact","sampleInterval":1,"window":60}"#
        defaults.set(Data(legacy.utf8), forKey: MenuBarDisplayConfig.defaultsKey)
        let loaded = MenuBarDisplayConfig.load(from: defaults)
        #expect(loaded.style == .curve)
        #expect(loaded.showTemperature && loaded.showRPM)
    }

    @Test("The temperature metric is live only when a temperature is shown")
    func temperatureMetricApplies() {
        // One rule for both styles: it follows the temperature switch, because that is the
        // only thing that decides whether a temperature is on screen at all.
        for style in [MenuBarStyle.numbers, .curve] {
            #expect(MenuBarDisplayConfig(style: style, showTemperature: true).temperatureMetricApplies)
            #expect(!MenuBarDisplayConfig(style: style, showTemperature: false, showRPM: true)
                        .temperatureMetricApplies)
            #expect(!MenuBarDisplayConfig(style: style, showTemperature: false, showRPM: false)
                        .temperatureMetricApplies)
        }
    }

    @Test("Curve sampling applies only while a sparkline is drawn")
    func curveSettingsApply() {
        #expect(!MenuBarDisplayConfig(style: .numbers, showTemperature: true, showRPM: true).curveSettingsApply)
        #expect(MenuBarDisplayConfig(style: .curve, showTemperature: true, showRPM: false).curveSettingsApply)
        #expect(MenuBarDisplayConfig(style: .curve, showTemperature: false, showRPM: true).curveSettingsApply)
        // Both switches off draws nothing, so the sampling settings are inert.
        #expect(!MenuBarDisplayConfig(style: .curve, showTemperature: false, showRPM: false).curveSettingsApply)
    }

    @Test("The unit suffix is live only when a number is drawn")
    func unitDisplayApplies() {
        #expect(MenuBarDisplayConfig(style: .numbers, showTemperature: true).unitDisplayApplies)
        #expect(MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: true).unitDisplayApplies)
        #expect(!MenuBarDisplayConfig(style: .numbers, showTemperature: false, showRPM: false).unitDisplayApplies)
        #expect(!MenuBarDisplayConfig(style: .curve, showTemperature: true, showRPM: true).unitDisplayApplies)
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
