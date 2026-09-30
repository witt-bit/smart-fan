import Foundation
import Testing
@testable import SmartFanCore

@Suite("Mode switch: deliberate choice and the cooldown between changes")
struct ModeSwitchTests {
    // MARK: - Cooldown (pure logic)

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("A change inside the cooldown is refused, but Default never is")
    func cooldownGate() {
        var cooldown = ModeSwitchCooldown(duration: 10)
        #expect(cooldown.allows("balanced", at: t0))
        cooldown.armed(at: t0)
        #expect(!cooldown.allows("performance", at: t0.addingTimeInterval(9)))
        // Default hands the fans back to Apple: the escape hatch when they are loud.
        #expect(cooldown.allows(FanProfile.silent.id, at: t0.addingTimeInterval(9)))
        #expect(cooldown.allows("performance", at: t0.addingTimeInterval(10)))
    }

    @Test("Choosing Default arms the cooldown too, so it cannot be flipped straight back")
    func defaultArmsCooldown() {
        var cooldown = ModeSwitchCooldown(duration: 10)
        cooldown.armed(at: t0)
        #expect(!cooldown.allows("balanced", at: t0.addingTimeInterval(5)))
    }

    @Test("The remaining time counts down, then reports nothing")
    func remaining() {
        var cooldown = ModeSwitchCooldown(duration: 10)
        #expect(cooldown.remaining(at: t0) == nil)
        cooldown.armed(at: t0)
        #expect(cooldown.remaining(at: t0) == 10)
        #expect(cooldown.remaining(at: t0.addingTimeInterval(9.5)) == 1)
        #expect(cooldown.remaining(at: t0.addingTimeInterval(10)) == nil)
    }

    // MARK: - Monitor behaviour (simulated SMC)

    /// A monitor whose fan commands are captured instead of written.
    private func capturingMonitor(_ f: ControlFixture,
                                  _ profile: FanProfile = .silent) -> (ThermalMonitor, () -> [Float]) {
        let monitor = f.monitor(profile)
        var targets: [Float] = []
        monitor.onFanCommand = { command in
            if case .setRPM(let rpm) = command { targets.append(rpm) }
        }
        return (monitor, { targets })
    }

    @Test("A deliberately chosen mode acts on the next tick, not after the sustained window")
    func switchSkipsSustainedWindow() {
        let f = ControlFixture()
        let (monitor, targets) = capturingMonitor(f)
        f.smc.temperature = 70            // above Balanced's 55 °C start
        monitor.switchProfile(.balanced)  // a deliberate choice
        f.tick(monitor, count: 1)         // one 100 ms tick
        // Balanced would otherwise sit out its 8 s sustained window before touching them.
        #expect(!targets().isEmpty)
    }

    @Test("Switching continues the ramp from the current speed, not from zero")
    func switchContinuesFromCurrentSpeed() {
        let f = ControlFixture()
        let (monitor, targets) = capturingMonitor(f)
        f.smc.temperature = 70
        f.smc.set("F0Ac", floatToSMCBytes(4800))   // the fans are already at 80 % of 6000
        monitor.switchProfile(.balanced)           // which tops out at 60 %
        f.tick(monitor, count: 1)
        // Ramps DOWN from 80 % toward 60 %: ~4785 RPM. Restarting the ramp at zero would
        // command the minimum (1000) first, slowing the fans before speeding them up.
        #expect((targets().first ?? 0) > 4000)
    }

    @Test("Without a mode change the sustained window still filters a fresh spike")
    func sustainedWindowStillApplies() {
        let f = ControlFixture()
        let (monitor, targets) = capturingMonitor(f, .balanced)
        f.smc.temperature = 70
        f.tick(monitor, count: 1)          // 0.1 s above the start temperature
        #expect(targets().isEmpty)         // not engaged yet: the filter is intact
        f.tick(monitor, count: 80)         // past Balanced's 8 s window
        #expect(!targets().isEmpty)
    }
}
