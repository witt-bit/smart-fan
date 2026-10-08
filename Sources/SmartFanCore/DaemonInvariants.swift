//
//  DaemonInvariants.swift
//  SmartFan
//
//  Pure, hardware-free decision logic for the Phase 3 daemon-enforced invariants:
//  a token-bucket rate limiter for SMC-writing verbs, and the thermal-safety-floor
//  state decision. Both take injected inputs (a clock, a temperature) so they unit
//  test without a bound socket or SMC. The DaemonServer performs the actual SMC and
//  state effects; these types only decide.
//

import Foundation

/// Token-bucket rate limiter for the daemon's SMC-writing verbs (`max`/`set`/`setfan`
/// — `auto`/reset is exempt). Burst capacity absorbs a legitimate pump ramp (~10/s,
/// coalescing under backpressure) while a flood drains it to the refill rate and gets
/// `rateLimited`. The clock is injected so the boundary is testable without waiting.
public struct RateLimiter {
    private let capacity: Double
    private let refillPerSecond: Double
    private var tokens: Double
    private var last: Date

    public init(capacity: Double = 20, refillPerSecond: Double = 10, now: Date) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
        self.last = now
    }

    /// Refill for elapsed time, then consume one token if available.
    public mutating func allow(now: Date) -> Bool {
        let elapsed = max(0, now.timeIntervalSince(last))
        last = now
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

/// The thermal safety floor's decision, given a sampled temperature and the current
/// hold/suspension state. The threshold is read from `FanProfile` rather than invented
/// here, and sits above the app's own protection ladder on purpose — see
/// `FanProfile.emergencyTempThreshold`.
public struct ThermalFloor {
    public let threshold: Float
    public let clearBelow: Float

    public init(threshold: Float = FanProfile.emergencyTempThreshold,
                hysteresis: Float = FanProfile.hysteresisDegrees) {
        self.threshold = threshold
        self.clearBelow = threshold - hysteresis
    }

    public enum Action: Equatable {
        case none
        case engage    // overheating while a below-max hold is active → override to max
        case restore   // cooled below the hysteresis point → restore the hold (or auto)
    }

    /// - suspended: is the floor currently overriding fans to max?
    /// - holdCommand: the active hold's command string, or nil for auto / no hold.
    public func evaluate(temp: Float, holdCommand: String?, suspended: Bool) -> Action {
        if suspended {
            // Restore only once cooled past the hysteresis point; otherwise keep max.
            return temp < clearBelow ? .restore : .none
        }
        // Engage only when overheating AND a hold pins fans below max. No hold (auto)
        // or an already-max hold needs no override.
        guard temp >= threshold, let cmd = holdCommand, cmd != "max" else { return .none }
        return .engage
    }
}

// MARK: - Daemon start and stop (ported from upstream 0.2.3.54, ThermalForge #31)

/// What a freshly started daemon does about the fans.
///
/// It starts holding nothing, so fans left under manual control — by a daemon killed
/// mid-hold, a crash, or a direct root SMC write made while no daemon ran — would stay pinned
/// with no thermal floor and no wake re-apply behind them. Release them to Apple. Adopting
/// instead is not possible: the SMC records no owner, so a CLI hold cannot be told from a dead
/// app's curve point, and per-fan targets do not fit one hold command.
///
/// The SMC access is injected, so this tests without root or hardware.
public enum StartupFanReconcile {
    public enum Outcome: Equatable {
        case alreadyAuto
        case reset
        /// The SMC could not be read, so we reset anyway: auto is the safe state.
        case resetAfterUnreadable
        case resetFailed(String)
    }

    public static func run(manualControlEngaged: () throws -> Bool,
                           resetAuto: () throws -> Void) -> Outcome {
        let unreadable: Bool
        do {
            guard try manualControlEngaged() else { return .alreadyAuto }
            unreadable = false
        } catch {
            unreadable = true
        }
        do {
            try resetAuto()
            return unreadable ? .resetAfterUnreadable : .reset
        } catch {
            return .resetFailed("\(error)")
        }
    }
}

/// What the daemon does on SIGTERM — a bootout, or a manual kill: release the fans only if it
/// was controlling them, so it never touches fans it does not own. A pending release counts: a
/// failed write it could not undo may have left the fans manual with no hold recorded.
public enum DaemonShutdown {
    public static func releasesFans(holding: Bool, safetySuspended: Bool,
                                    releasePending: Bool = false) -> Bool {
        holding || safetySuspended || releasePending
    }
}
