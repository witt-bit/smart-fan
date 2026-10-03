//
//  HighTempProtection.swift
//  SmartFan
//
//  The high-temperature protection ladder: a graduated fan response for the range
//  between "the selected mode is not keeping the die cool" and "the fans are not
//  keeping up at all". Replaces the single 95 °C threshold that maxed the fans on a
//  single reading, which flapped against a die sensor that swings several degrees per
//  second (see docs/high-temp-protection-plan.md §2).
//
//  ```
//    ≥ 90 °C held 10 s              → half fan speed
//    ≥ 95 °C held 30 s, at half     → full fan speed
//    full held 30 s, then < 95 °C   → half again
//    half held 30 s, then < 90 °C   → stop, back to the mode / the system
//  ```
//
//  Pure decision logic with an injected time step, like `ThermalFloor`: the monitor
//  performs the SMC writes, this type only decides. Every step is held for at least
//  `stepHold`, so a reading that tumbles across a threshold cannot make the fans
//  change speed every tick.
//

import Foundation

public struct HighTempProtection {

    // MARK: - Settings

    /// What the user asked for in the preferences.
    public struct Settings: Equatable, Sendable {
        /// The "high-temperature protection" switch. Off means the ladder never runs.
        public var enabled: Bool
        /// Whether the ladder also runs while the selected mode hands the fans to the
        /// system ("Default"). Off by default: that mode means the system owns fan
        /// control, and overriding it would put two controllers on one fan.
        public var runsWhileHandedOff: Bool

        public init(enabled: Bool = true, runsWhileHandedOff: Bool = false) {
            self.enabled = enabled
            self.runsWhileHandedOff = runsWhileHandedOff
        }
    }

    // MARK: - Ladder

    /// Where the ladder currently sits.
    public enum Stage: Equatable, Sendable {
        case off
        case halfSpeed
        case fullSpeed
    }

    /// What the monitor should do with the fans this tick.
    public enum Action: Equatable, Sendable {
        case none
        /// Command half of the fan's maximum.
        case halfSpeed
        /// Command the fan's maximum.
        case fullSpeed
        /// Hand the fans back: the selected mode resumes control next tick, which for
        /// a hands-off mode means returning them to the system.
        case stop
    }

    /// Temperature at which the ladder starts, held for `startHold`.
    public static let startTemp: Float = 90
    public static let startHold: TimeInterval = 10
    /// Temperature that escalates the half-speed step, held for `fullHold`.
    public static let fullTemp: Float = 95
    public static let fullHold: TimeInterval = 30
    /// Minimum time each step is held before it may step down again.
    public static let stepHold: TimeInterval = 30
    /// How far below `startTemp` the reading has to fall before a step may stop.
    ///
    /// Without a gap the stop line sits exactly where the reading sits when the machine is
    /// working hard: measured over 60 s on Mac16,1 the reading's median was 90.8 °C, 55 % of
    /// samples were above the line, and its longest run below it was 23 s against the 30 s the
    /// stop needs — so a ladder that could engage could never release. A gap of 5 °C is what
    /// the single-threshold latch upstream replaced used, and it is what makes the stop reachable.
    public static let releaseGap: Float = 5
    /// How long the reading may sit below a threshold before that hold restarts.
    ///
    /// Without it a single 100 ms sample below the line threw away a nearly-complete
    /// window: the measured die reading on this M4 moves 6–11 °C in two seconds, so
    /// "30 consecutive seconds" was effectively unreachable and the ladder never left
    /// half speed. A hold now measures the time the reading has actually spent at or
    /// above its threshold, and only restarts once the reading has been below it for
    /// longer than this.
    public static let dipTolerance: TimeInterval = 3
    /// Accumulated 100 ms ticks do not land exactly on a boundary — 0.1 has no exact
    /// binary form, so a hundred of them sum a hair under 10 — and a hold must be met
    /// on the tick the user's number says, not one tick later.
    private static let tolerance: TimeInterval = 1e-6

    // MARK: - State

    /// How much of the recent past the reading has spent at or above a threshold.
    /// Dips shorter than `dipTolerance` are ignored; only the time actually at or above
    /// the threshold is counted, so a reading that spends half its time below the line
    /// takes twice as long to satisfy a hold.
    private struct Hold {
        private(set) var accumulated: TimeInterval = 0
        private var belowFor: TimeInterval = 0

        mutating func advance(temp: Float, threshold: Float, elapsed: TimeInterval) {
            guard temp < threshold else {
                accumulated += elapsed
                belowFor = 0
                return
            }
            belowFor += elapsed
            if belowFor > HighTempProtection.dipTolerance { accumulated = 0 }
        }

        func reached(_ hold: TimeInterval) -> Bool {
            accumulated >= hold - HighTempProtection.tolerance
        }

        mutating func reset() {
            accumulated = 0
            belowFor = 0
        }
    }

    public private(set) var stage: Stage = .off
    /// Time at or above `startTemp`.
    private var aboveStart = Hold()
    /// Time at or above `fullTemp`.
    private var aboveFull = Hold()
    /// Time spent in the current step.
    private var inStage: TimeInterval = 0

    public init() {}

    /// Whether the ladder is holding a fan speed of its own.
    public var isEngaged: Bool { stage != .off }

    /// Advance one tick.
    ///
    /// - temp: the temperature the ladder watches.
    /// - elapsed: seconds since the previous call.
    /// - handedOff: the selected mode has handed fan control to the system.
    public mutating func evaluate(temp: Float, elapsed: TimeInterval,
                                  handedOff: Bool, settings: Settings) -> Action {
        // Switching the protection off — or handing the fans to the system — drops out
        // at once, wherever the ladder is. Leaving fans pinned at half speed after the
        // user turned the feature off would be worse than the overshoot it guards.
        guard settings.enabled, !(handedOff && !settings.runsWhileHandedOff) else {
            let wasEngaged = isEngaged
            reset()
            return wasEngaged ? .stop : .none
        }

        // Held readings, not single samples: a brief dip does not restart the climb.
        aboveStart.advance(temp: temp, threshold: Self.startTemp, elapsed: elapsed)
        aboveFull.advance(temp: temp, threshold: Self.fullTemp, elapsed: elapsed)
        inStage += elapsed

        switch stage {
        case .off:
            guard aboveStart.reached(Self.startHold) else { return .none }
            stage = .halfSpeed
            inStage = 0
            return .halfSpeed

        case .halfSpeed:
            // Escalate: the half-speed step is not holding the temperature.
            if aboveFull.reached(Self.fullHold) {
                stage = .fullSpeed
                inStage = 0
                return .fullSpeed
            }
            // Re-decide once the step has been held. Below the release line the ladder is
            // finished; in the 90–95 band the half-speed step runs another window.
            if inStage >= Self.stepHold - Self.tolerance {
                inStage = 0
                if temp < Self.startTemp - Self.releaseGap {
                    reset()
                    return .stop
                }
            }
            return .none

        case .fullSpeed:
            // Only step down once the temperature has actually left the escalate point,
            // and then to half speed rather than straight off, so the fans come back
            // down in the same steps they went up.
            if inStage >= Self.stepHold - Self.tolerance {
                inStage = 0
                if temp < Self.fullTemp {
                    stage = .halfSpeed
                    return .halfSpeed
                }
            }
            return .none
        }
    }

    private mutating func reset() {
        stage = .off
        aboveStart.reset()
        aboveFull.reset()
        inStage = 0
    }
}
