//
//  MenuBarHistory.swift
//  SmartFan
//
//  A rolling window of menu bar samples for the curve styles. In-memory only:
//  the window is at most a couple hundred points, it is purely a display aid, and
//  persisting it would add disk I/O for no benefit (see
//  docs/menu-bar-display-plan.md §7).
//

import Foundation

public struct MenuBarHistory: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public var time: Date
        /// The config's temperature metric at that moment (nil when unreadable).
        public var temperature: Float?
        /// The averaged fan RPM at that moment (nil when unreadable).
        public var rpm: Float?

        public init(time: Date, temperature: Float?, rpm: Float?) {
            self.time = time
            self.temperature = temperature
            self.rpm = rpm
        }
    }

    public private(set) var samples: [Sample] = []

    /// Hard cap on the window, so a hand-edited config cannot grow the buffer past
    /// what the UI can ever show.
    public static let maxWindow: TimeInterval = 180
    /// Safety rail on the point count.
    public static let maxPoints = 4096

    public init() {}

    /// Drop everything: app restart, or a window change that invalidates the run.
    public mutating func reset() { samples.removeAll() }

    /// Append a sample, enforcing the sampling interval and the window.
    ///
    /// - A gap longer than the window (sleep/wake) **discards the stale run**
    ///   rather than drawing one straight line across the hole (plan §7).
    /// - A sample arriving sooner than `interval` is dropped, so the curve keeps a
    ///   stable resolution regardless of the faster UI/status cadence.
    public mutating func append(_ sample: Sample, interval: TimeInterval, window: TimeInterval) {
        guard interval > 0, interval.isFinite, window > 0, window.isFinite else { reset(); return }
        let capped = min(window, Self.maxWindow)
        if let last = samples.last {
            let gap = sample.time.timeIntervalSince(last.time)
            if gap > capped { samples.removeAll() }
            else if gap < interval { return }
        }
        samples.append(sample)
        trim(window: window)
    }

    /// Truncate to the window. Called on append and whenever the window shrinks.
    public mutating func trim(window: TimeInterval) {
        guard window > 0, window.isFinite else { reset(); return }
        let capped = min(window, Self.maxWindow)
        if let last = samples.last {
            let cutoff = last.time.addingTimeInterval(-capped)
            samples.removeAll { $0.time < cutoff }
        }
        if samples.count > Self.maxPoints { samples.removeFirst(samples.count - Self.maxPoints) }
    }
}
