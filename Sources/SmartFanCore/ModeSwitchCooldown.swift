//
//  ModeSwitchCooldown.swift
//  SmartFan
//
//  Minimum dwell time between mode changes.
//

import Foundation

/// Refuses a mode change made too soon after the previous one.
///
/// Switching faster than the ramp can act produces acoustic whiplash and a burst of
/// daemon commands without changing the outcome — and since a deliberate choice now
/// skips the sustained trigger, rapid switching would make the fans lurch from one
/// target to the next.
///
/// Default is never refused: it hands the fans back to Apple and is the escape hatch
/// when they are loud. Choosing it still arms the cooldown, so Default and a
/// controlling mode cannot be flipped back and forth either.
public struct ModeSwitchCooldown: Equatable, Sendable {
    public let duration: TimeInterval

    /// When another controlling mode may be chosen, or nil when free.
    public private(set) var lockedUntil: Date?

    public init(duration: TimeInterval) {
        self.duration = duration
    }

    /// Whether a change to `profileID` is allowed at `now`.
    public func allows(_ profileID: String, at now: Date) -> Bool {
        guard let lockedUntil, now < lockedUntil else { return true }
        return profileID == FanProfile.silent.id
    }

    /// Arm the cooldown after an accepted change.
    public mutating func armed(at now: Date) {
        lockedUntil = now.addingTimeInterval(duration)
    }

    /// Whole seconds left, or nil when free. Lets the UI explain a refused click.
    public func remaining(at now: Date) -> Int? {
        guard let lockedUntil, lockedUntil > now else { return nil }
        return Int(lockedUntil.timeIntervalSince(now).rounded(.up))
    }
}
