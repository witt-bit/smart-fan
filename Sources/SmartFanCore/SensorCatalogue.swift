//
//  SensorCatalogue.swift
//  SmartFan
//
//  What each probed SMC temperature key is, and which reading consumes it.
//
//  The app works with three layers, and until now they existed only in prose spread across
//  comments, a calibration document and a hardcoded key table:
//
//   1. the raw keys the SMC publishes (`ThermalStatus.rawTemperatures`, `sensorDrops`),
//   2. the derived readings the panel and the menu bar show (`displayedCPUTemp`,
//      `displayedGPUTemp`, `averageTemp`, `batteryTemp`),
//   3. the number the fan logic compares its thresholds against (`safetyPeakTemp`).
//
//  Layer 3 is not layer 2. The control basis is the maximum over the `TC`/`Tp`/`TG`/`Tg`
//  prefixes, which includes keys that are not core temperatures, so it reads several degrees
//  above the CPU row — measured 3.1–9.6 °C (7 average) on Mac16,1. This type is the single
//  record of which key belongs to which layer, so the preferences can list the raw sensors
//  and the two bases can be compared instead of argued about.
//
//  See docs/thermal-sensor-calibration-20260924.md and
//  docs/high-temp-protection-plan.md §5, and docs/sensor-list-plan.md for the design.
//

import Foundation

/// What one probed key is, and what reads it.
public struct SensorRole: Equatable, Sendable {

    /// What the key measures.
    ///
    /// The distinction between a core temperature and the rest of its family is the whole
    /// reason this type exists: the SMC exposes several keys per core, and only one of them
    /// is the core. The others — and the SoC-level keys — are real readings of a different
    /// quantity, and they are what the control basis picks up.
    public enum Kind: String, CaseIterable, Sendable {
        /// A CPU core temperature, per the per-chip calibrated table.
        case cpuCore
        /// A `TC`/`Tp`/`Te` key on a chip with no calibrated table: the prefix grouping is all
        /// we have, and it is what the CPU row falls back to.
        case cpuPrefix
        /// In the CPU families but not a core temperature — the rest of a core's group, and
        /// the SoC-level keys such as `TCDX`/`TCMb`.
        case cpuDerived
        case gpu
        case memory
        case ssd
        case ambient
        case battery
        /// Power delivery (`TPDX`).
        case power
        /// Probed, but not any of the above (`TS0P` and other proximity keys).
        case other
    }

    /// A reading that consumes this key.
    public enum Use: String, CaseIterable, Sendable {
        /// The CPU row and the menu bar headline.
        case cpu
        case gpu
        case ram
        case ssd
        case ambient
        /// The `batteryTemp` metric ("feels-like").
        case feelsLike
        /// The `averageTemp` metric.
        case average
        /// The fan logic: the mode curves, the sustained window and the high-temperature
        /// ladder all compare their thresholds against the maximum of these keys.
        case control
    }

    public let kind: Kind
    /// In `Use.allCases` order, so the raw list and its tests are stable to compare.
    public let uses: [Use]

    public init(kind: Kind, uses: [Use]) {
        self.kind = kind
        self.uses = uses
    }
}

// MARK: - Classification

public extension SensorRole {

    /// The prefixes the fan logic watches. Upstream's list, which deliberately omits the
    /// `Te*` efficiency cores; kept as is, because changing it would move every tuned
    /// threshold — the curves' 55/65/85 °C and the ladder's 90/95 °C — at once.
    /// `FanControl.safetyTempKeys` is derived from this, so the two cannot drift.
    static let controlPrefixes = ["TC", "Tp", "TG", "Tg"]

    /// The key families the CPU row is built from, in the order they are tried.
    static let cpuPrefixes = ["TC", "Tp", "Te"]

    /// True when the fan logic compares its thresholds against this key.
    static func isControlBasis(_ key: String) -> Bool {
        controlPrefixes.contains { key.hasPrefix($0) }
    }

    /// What the key is, given the chip's calibrated core table (empty on chips without one,
    /// where the prefix grouping is the only information available).
    static func kind(of key: String, coreKeys: Set<String>) -> Kind {
        if coreKeys.contains(key) { return .cpuCore }
        if cpuPrefixes.contains(where: { key.hasPrefix($0) }) {
            // With a table, anything else in these families is a different quantity. Without
            // one, the family is all we have — and it is what the CPU row uses as well.
            return coreKeys.isEmpty ? .cpuPrefix : .cpuDerived
        }
        if key.hasPrefix("TG") || key.hasPrefix("Tg") { return .gpu }
        if ["TR", "Tm", "TM"].contains(where: { key.hasPrefix($0) }) { return .memory }
        if key.hasPrefix("TH") { return .ssd }
        if key.hasPrefix("TA") { return .ambient }
        if key.hasPrefix("TB") { return .battery }
        if key.hasPrefix("TP") { return .power }
        return .other
    }

    static func role(of key: String, coreKeys: Set<String>) -> SensorRole {
        let kind = kind(of: key, coreKeys: coreKeys)
        var uses: [Use]
        switch kind {
        case .cpuCore, .cpuPrefix: uses = [.cpu, .average]
        case .cpuDerived: uses = [.average]
        case .gpu: uses = [.gpu, .average]
        case .memory: uses = [.ram, .average]
        case .ssd: uses = [.ssd, .average]
        case .ambient: uses = [.ambient, .average]
        case .battery: uses = [.feelsLike, .average]
        case .power, .other: uses = [.average]
        }
        if isControlBasis(key) { uses.append(.control) }
        return SensorRole(kind: kind, uses: uses)
    }
}

// MARK: - Why a probed key has no reading

/// Why a probed key did not become a usable reading.
public enum SensorDrop: Equatable, Sendable {
    /// The key is not published on this Mac.
    case absent
    /// Read, but outside the sane 0–150 °C range: a placeholder or junk value.
    case outOfRange(Float)
    /// IOHID identifies this key as a battery sensor, whatever its prefix claims.
    case batteryKey
    /// A die key below 10 °C: a gated core's placeholder, not a temperature.
    case belowDieFloor
}

// MARK: - One row of the sensor list

/// One probed key, as the preferences' sensor list needs it: the number the SMC gave, whether
/// the app kept it, why not, and what the key is.
public struct SensorReading: Equatable, Sendable {
    public let key: String
    /// The value as read, before the sensor filter. Includes readings that were then dropped.
    public let raw: Float?
    /// The value the readings and the average work with. nil when the key was dropped.
    public let accepted: Float?
    /// Why there is no `accepted` value. nil means the key was kept.
    public let drop: SensorDrop?
    public let role: SensorRole

    public init(key: String, raw: Float?, accepted: Float?, drop: SensorDrop?, role: SensorRole) {
        self.key = key
        self.raw = raw
        self.accepted = accepted
        self.drop = drop
        self.role = role
    }
}

public extension ThermalStatus {

    /// One row per key the app probes — including keys that read nothing, so the list can
    /// account for every key rather than leaving gaps to guess at.
    ///
    /// Ordered by role, then by key: the list must not jump around between refreshes, and a
    /// reading that moves between refreshes is the thing this list exists to make visible.
    func sensorReadings(coreKeys: Set<String> = ThermalStatus.validatedCoreKeys) -> [SensorReading] {
        FanControl.thermalKeys
            .map { key in
                let raw = rawTemperatures[key]
                return SensorReading(key: key,
                                     raw: raw,
                                     accepted: temperatures[key],
                                     drop: raw == nil ? .absent : sensorDrops[key],
                                     role: SensorRole.role(of: key, coreKeys: coreKeys))
            }
            .sorted { left, right in
                let (l, r) = (SensorRole.Kind.allCases.firstIndex(of: left.role.kind) ?? 0,
                              SensorRole.Kind.allCases.firstIndex(of: right.role.kind) ?? 0)
                return l == r ? left.key < right.key : l < r
            }
    }
}
