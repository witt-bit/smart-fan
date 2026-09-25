import Testing
@testable import SmartFanCore

@Suite("Fixed Rate range")
struct FixedRateTests {
    private func fan(min: Int, max: Int) -> ThermalStatus.FanStatus {
        .init(index: 0, actualRPM: 0, targetRPM: 0, minRPM: min, maxRPM: max, mode: "auto")
    }

    @Test("Clamps to the reported range")
    func clamps() {
        let f = fan(min: 2317, max: 6550)
        #expect(FanProfile.clampFixedRPM(3000, fan: f) == 3000)
        #expect(FanProfile.clampFixedRPM(100, fan: f) == 2317)
        #expect(FanProfile.clampFixedRPM(99999, fan: f) == 6550)
    }

    @Test("An unknown or unreported range passes the value through instead of stopping the fans")
    func unknownRange() {
        #expect(FanProfile.clampFixedRPM(3000, fan: nil) == 3000)
        #expect(FanProfile.clampFixedRPM(3000, fan: fan(min: 0, max: 0)) == 3000)
        // Negative input still floors at zero.
        #expect(FanProfile.clampFixedRPM(-5, fan: nil) == 0)
    }

    @Test("The slider range falls back when the hardware reports none")
    func range() {
        #expect(FanProfile.fixedRPMRange(fan: fan(min: 2317, max: 6550)) == 2317...6550)
        #expect(FanProfile.fixedRPMRange(fan: nil) == FanProfile.fallbackFixedRPMRange)
        #expect(FanProfile.fixedRPMRange(fan: fan(min: 0, max: 0)) == FanProfile.fallbackFixedRPMRange)
    }
}
