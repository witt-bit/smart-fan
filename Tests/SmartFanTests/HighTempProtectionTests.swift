import Foundation
import Testing
@testable import SmartFanCore

@Suite("High-temperature protection ladder")
struct HighTempProtectionTests {
    /// One tick is 100 ms, the monitor's real interval.
    private let step: TimeInterval = 0.1

    private func advance(_ ladder: inout HighTempProtection, temp: Float, seconds: TimeInterval,
                         handedOff: Bool = false,
                         settings: HighTempProtection.Settings = .init())
        -> HighTempProtection.Action {
        var action = HighTempProtection.Action.none
        for _ in 0..<Int((seconds / step).rounded()) {
            action = ladder.evaluate(temp: temp, elapsed: step,
                                     handedOff: handedOff, settings: settings)
        }
        return action
    }

    /// Bring the ladder to half speed from cold.
    private func engagedAtHalfSpeed(_ ladder: inout HighTempProtection) {
        _ = advance(&ladder, temp: HighTempProtection.startTemp, seconds: HighTempProtection.startHold)
    }

    @Test("A reading below the entry point never engages")
    func belowEntry() {
        var ladder = HighTempProtection()
        #expect(advance(&ladder, temp: 89.9, seconds: 600) == .none)
        #expect(ladder.stage == .off)
    }

    @Test("Nine seconds of 90 °C is not enough; ten is")
    func entryIsHeld() {
        var ladder = HighTempProtection()
        #expect(advance(&ladder, temp: 90, seconds: 9) == .none)
        #expect(ladder.stage == .off)
        #expect(advance(&ladder, temp: 90, seconds: 1) == .halfSpeed)
        #expect(ladder.stage == .halfSpeed)
    }

    @Test("A single tick below the entry point restarts the hold")
    func dipRestartsEntry() {
        var ladder = HighTempProtection()
        _ = advance(&ladder, temp: 90, seconds: 9.5)
        _ = advance(&ladder, temp: 85, seconds: step)
        #expect(advance(&ladder, temp: 90, seconds: 9) == .none)
        #expect(ladder.stage == .off)
        #expect(advance(&ladder, temp: 90, seconds: 1) == .halfSpeed)
    }

    @Test("At half speed, thirty seconds at 95 °C escalates to full")
    func escalatesToFull() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        // In the escalator's band the half-speed step holds first.
        #expect(advance(&ladder, temp: 95, seconds: 29) == .none)
        #expect(ladder.stage == .halfSpeed)
        #expect(advance(&ladder, temp: 95, seconds: 1) == .fullSpeed)
        #expect(ladder.stage == .fullSpeed)
    }

    @Test("Escalation also needs the temperature, not just time at half speed")
    func escalationNeedsHeat() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        // Half speed for a long time in the 90–95 band never reaches full.
        #expect(advance(&ladder, temp: 94, seconds: 600) == .none)
        #expect(ladder.stage == .halfSpeed)
    }

    @Test("At half speed, thirty seconds below 90 °C stops the ladder")
    func halfSpeedStops() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        // The step is held for its full window even though the reading has fallen.
        #expect(advance(&ladder, temp: 85, seconds: 29) == .none)
        #expect(ladder.stage == .halfSpeed)
        #expect(advance(&ladder, temp: 85, seconds: 1) == .stop)
        #expect(ladder.stage == .off)
    }

    @Test("In the 90–95 band half speed keeps running another window")
    func halfSpeedKeepsRunning() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        #expect(advance(&ladder, temp: 92, seconds: 30) == .none)
        #expect(ladder.stage == .halfSpeed)
        // A second, and a twentieth, window still does not stop it.
        #expect(advance(&ladder, temp: 92, seconds: 600) == .none)
        #expect(ladder.stage == .halfSpeed)
    }

    @Test("Full speed holds while the reading stays at 95 °C")
    func fullSpeedHolds() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        _ = advance(&ladder, temp: 95, seconds: HighTempProtection.fullHold)
        #expect(ladder.stage == .fullSpeed)
        #expect(advance(&ladder, temp: 96, seconds: 300) == .none)
        #expect(ladder.stage == .fullSpeed)
    }

    @Test("Full speed steps down to half, not straight off, once the reading leaves 95 °C")
    func fullSpeedStepsDown() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        _ = advance(&ladder, temp: 95, seconds: HighTempProtection.fullHold)
        #expect(ladder.stage == .fullSpeed)
        #expect(advance(&ladder, temp: 93, seconds: 30) == .halfSpeed)
        #expect(ladder.stage == .halfSpeed)
        // Then the half-speed window before it may stop.
        #expect(advance(&ladder, temp: 93, seconds: 30) == .none)
        #expect(advance(&ladder, temp: 84, seconds: 30) == .stop)
        #expect(ladder.stage == .off)
    }

    @Test("The whole descent runs in the documented order")
    func descentOrder() {
        var ladder = HighTempProtection()
        var actions: [HighTempProtection.Action] = []
        actions.append(advance(&ladder, temp: 91, seconds: 10))    // half
        actions.append(advance(&ladder, temp: 97, seconds: 30))    // full
        actions.append(advance(&ladder, temp: 92, seconds: 30))    // half
        actions.append(advance(&ladder, temp: 86, seconds: 30))    // stop
        #expect(actions == [.halfSpeed, .fullSpeed, .halfSpeed, .stop])
        #expect(ladder.stage == .off)
    }

    @Test("Turning the protection off stops the ladder at once")
    func switchingOffStops() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        let off = HighTempProtection.Settings(enabled: false)
        // One tick: the stop is reported once, then the ladder is already down.
        #expect(advance(&ladder, temp: 97, seconds: step, settings: off) == .stop)
        #expect(ladder.stage == .off)
        // And it stays off however hot it gets.
        #expect(advance(&ladder, temp: 105, seconds: 600, settings: off) == .none)
        #expect(ladder.stage == .off)
    }

    @Test("Switching off before it ever engaged reports nothing")
    func switchingOffWhileIdle() {
        var ladder = HighTempProtection()
        let off = HighTempProtection.Settings(enabled: false)
        #expect(advance(&ladder, temp: 99, seconds: 600, settings: off) == .none)
    }

    @Test("A hands-off mode is left alone by default")
    func handsOffIgnored() {
        var ladder = HighTempProtection()
        #expect(advance(&ladder, temp: 99, seconds: 600, handedOff: true) == .none)
        #expect(ladder.stage == .off)
    }

    @Test("A hands-off mode runs the ladder when the user asks for it")
    func handsOffOptional() {
        var ladder = HighTempProtection()
        let settings = HighTempProtection.Settings(enabled: true, runsWhileHandedOff: true)
        #expect(advance(&ladder, temp: 90, seconds: 10, handedOff: true, settings: settings) == .halfSpeed)
        #expect(ladder.stage == .halfSpeed)
    }

    @Test("Handing the fans to the system mid-ladder stops it")
    func handingOffStops() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        #expect(advance(&ladder, temp: 97, seconds: step, handedOff: true) == .stop)
        #expect(ladder.stage == .off)
    }

    @Test("A dropped reading cancels an in-progress escalation")
    func droppedReadingCancelsEscalation() {
        var ladder = HighTempProtection()
        engagedAtHalfSpeed(&ladder)
        _ = advance(&ladder, temp: 95, seconds: 25)
        _ = advance(&ladder, temp: 88, seconds: 1)   // below 95: the 30 s restarts
        #expect(advance(&ladder, temp: 95, seconds: 25) == .none)
        #expect(ladder.stage == .halfSpeed)
        #expect(advance(&ladder, temp: 95, seconds: 5) == .fullSpeed)
    }
}
