//
//  FanControl.swift
//  SmartFan
//
//  Core fan control operations: unlock, set speed, reset, status, discover.
//

import Foundation

// MARK: - Types

public enum SmartFanError: Error, CustomStringConvertible {
    case smcConnectionFailed
    case unlockFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case rpmOutOfRange(requested: Float, min: Float, max: Float)
    case invalidFanIndex(index: Int, count: Int)
    case invalidRPM(Float)

    public var description: String {
        switch self {
        case .smcConnectionFailed:
            return "Failed to connect to AppleSMC. Is this a Mac with SMC?"
        case .unlockFailed(let detail):
            return "Fan unlock failed: \(detail)"
        case .readFailed(let key):
            return "Failed to read SMC key: \(key)"
        case .writeFailed(let key):
            return "Failed to write SMC key: \(key). Run with sudo."
        case .rpmOutOfRange(let req, let min, let max):
            return "RPM \(Int(req)) is out of range [\(Int(min))–\(Int(max))]"
        case .invalidFanIndex(let index, let count):
            return "Invalid fan index \(index); this Mac has \(count) fan(s), numbered from 0"
        case .invalidRPM(let rpm):
            return "Invalid RPM \(rpm); expected a finite, nonnegative value within the supported numeric range"
        }
    }
}

public struct FanInfo {
    public let index: Int
    public let actualRPM: Float
    public let targetRPM: Float
    public let minRPM: Float
    public let maxRPM: Float
    public let mode: String
}

/// An accepted target, returned by the writer rather than read from lagging SMC registers.
public struct FanRPM: Codable, Equatable {
    public let index: Int
    public let rpm: Int

    public init(index: Int, rpm: Int) { self.index = index; self.rpm = rpm }
}

public struct ThermalStatus: Encodable {
    public let fans: [FanStatus]
    public let temperatures: [String: Float]
    /// Average of every sensor in `temperatures` — the menu bar "average" metric.
    /// nil when no sensor read (never 0, so "no data" stays distinguishable).
    public let averageTemp: Float?
    /// Battery temperature — the menu bar "feels-like" metric. nil when this Mac
    /// exposes no readable battery sensor.
    public let batteryTemp: Float?
    /// Average of the fans whose `F{i}Ac` read succeeded. nil when none read, so a
    /// single failed fan read never drags the average down.
    public let fanRPM: Float?
    /// Every probed key's value as the SMC reported it, whether or not `SMCSensorFilter`
    /// kept it. `temperatures` is the kept subset. For the preferences' sensor list, which
    /// has to be able to show a dropped reading — and for nothing else: no reading and no
    /// fan decision looks at this.
    public let rawTemperatures: [String: Float]
    /// Why a probed key has no usable reading. A key in neither this nor `rawTemperatures`
    /// is simply not published on this Mac.
    public let sensorDrops: [String: SensorDrop]

    /// The wire format is unchanged: these two are for the preferences' sensor list only, and
    /// the daemon's status JSON (and the CLI's `status` output) has no use for ~66 raw keys.
    enum CodingKeys: String, CodingKey {
        case fans, temperatures, averageTemp, batteryTemp, fanRPM
    }

    public init(fans: [FanStatus], temperatures: [String: Float],
                averageTemp: Float? = nil, batteryTemp: Float? = nil, fanRPM: Float? = nil,
                rawTemperatures: [String: Float] = [:],
                sensorDrops: [String: SensorDrop] = [:]) {
        self.fans = fans
        self.temperatures = temperatures
        self.averageTemp = averageTemp
        self.batteryTemp = batteryTemp
        self.fanRPM = fanRPM
        self.rawTemperatures = rawTemperatures
        self.sensorDrops = sensorDrops
    }

    public struct FanStatus: Encodable {
        public let index: Int
        public let actualRPM: Int
        public let targetRPM: Int
        public let minRPM: Int
        public let maxRPM: Int
        public let mode: String
    }
}

extension ThermalStatus {
    /// Peak of the CPU (`TC`/`Tp`) and GPU (`TG`/`Tg`) sensors — the temperature the
    /// thermal safety floor watches. Single source of truth so the client
    /// `ThermalMonitor` and the daemon's floor read the identical value; mirroring
    /// can't drift because it's the same code.
    public var safetyPeakTemp: Float {
        func peak(_ prefixes: [String]) -> Float {
            temperatures.filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
                .values.max() ?? 0
        }
        return max(peak(["TC", "Tp"]), peak(["TG", "Tg"]))
    }
}

public struct DiscoveredKey {
    public let key: String
    public let size: UInt32
    public let type: String
    public let bytes: [UInt8]
}

// MARK: - Fan Control

public final class FanControl {
    private let smc: SMCConnection
    private let logger: TFLogger?
    /// Which mode key works on this hardware (detected at init)
    private let modeKeyTemplate: String
    /// Whether Ftst unlock is available (M1-M4) or not (M5+)
    private let hasFtst: Bool

    public convenience init() throws {
        guard let connection = SMCConnection() else {
            throw SmartFanError.smcConnectionFailed
        }
        self.init(smc: connection, logger: .shared)
    }

    /// Injected SMC tests do not write the user's runtime log.
    init(smc: SMCConnection, logger: TFLogger? = nil) {
        self.smc = smc
        self.logger = logger

        // Detect hardware: which mode key exists?
        // M5 Max uses F%dmd (lowercase), M1-M4 use F%dMd (uppercase)
        let lowerResult = smc.readKey(SMCFanKey.key(SMCFanKey.modeLower, fan: 0))
        if lowerResult.success {
            self.modeKeyTemplate = SMCFanKey.modeLower
        } else {
            self.modeKeyTemplate = SMCFanKey.modeUpper
        }

        // Check if Ftst exists (M1-M4 unlock mechanism)
        if let info = smc.getKeyInfo(SMCFanKey.forceTest), info.size > 0 {
            self.hasFtst = true
        } else {
            self.hasFtst = false
        }
    }

    // MARK: - Fan Count

    public func fanCount() throws -> Int {
        let result = smc.readKey(SMCFanKey.count)
        guard result.success, !result.bytes.isEmpty else {
            throw SmartFanError.readFailed(SMCFanKey.count)
        }
        return Int(result.bytes[0])
    }

    // MARK: - Read Fan Info

    func validateFanIndex(_ index: Int) throws {
        let count = try fanCount()
        guard index >= 0, index < count else {
            throw SmartFanError.invalidFanIndex(index: index, count: count)
        }
    }

    static func validateRPM(_ rpm: Float) throws {
        guard rpm >= 0, Int(exactly: rpm.rounded(.towardZero)) != nil else {
            throw SmartFanError.invalidRPM(rpm)
        }
    }

    public func fanInfo(_ index: Int) throws -> FanInfo {
        try readFanInfo(index).info
    }

    /// Fan info plus the raw `F{i}Ac` read (nil when it failed). `status()` uses it
    /// so one read of the actual key feeds both the fan row and the menu bar's RPM
    /// average, instead of reading the key twice per fan per sweep.
    private func readFanInfo(_ index: Int) throws -> (info: FanInfo, actual: Float?) {
        try validateFanIndex(index)
        let actual = readFanFloat(index, template: SMCFanKey.actual)
        let target = readFanFloat(index, template: SMCFanKey.target) ?? 0
        let minimum = readFanFloat(index, template: SMCFanKey.minimum) ?? 0
        let maximum = readFanFloat(index, template: SMCFanKey.maximum) ?? 0

        let modeKey = SMCFanKey.key(modeKeyTemplate, fan: index)
        let modeResult = smc.readKey(modeKey)
        let modeValue = modeResult.success && !modeResult.bytes.isEmpty ? modeResult.bytes[0] : 0
        let mode: String
        switch modeValue {
        case 0: mode = "auto"
        case 1: mode = "manual"
        case 3: mode = "system"
        default: mode = "unknown(\(modeValue))"
        }

        let info = FanInfo(
            index: index,
            actualRPM: actual ?? 0,
            targetRPM: target,
            minRPM: minimum,
            maxRPM: maximum,
            mode: mode
        )
        return (info, actual)
    }

    // MARK: - Unlock

    /// Unlock fans for manual control.
    /// On M1-M4: writes Ftst=1, then polls until mode write succeeds.
    /// On M5+: Ftst doesn't exist, attempts direct mode write.
    private func unlockFans(count: Int) throws {
        try acquireManualMode(indices: Array(0..<count))
    }

    /// Unlock a single fan for manual control
    private func unlockSingleFan(_ index: Int) throws {
        try acquireManualMode(indices: [index])
    }

    private func acquireManualMode(indices: [Int]) throws {
        try FanHandoff.acquire(
            indices: indices, hasFtst: hasFtst,
            modeKey: { SMCFanKey.key(self.modeKeyTemplate, fan: $0) },
            readMode: { index in
                let result = self.smc.readKey(SMCFanKey.key(self.modeKeyTemplate, fan: index))
                return result.success && result.size == 1 ? result.bytes.first : nil
            },
            write: { self.smc.writeKey($0, bytes: $1) }
        )
    }

    // MARK: - Set Speed

    /// Set all fans to maximum RPM
    public func setMax() throws {
        let count = try fanCount()
        try unlockFans(count: count)

        for i in 0..<count {
            let info = try fanInfo(i)
            let maxRPM = info.maxRPM > 0 ? info.maxRPM : 7826

            let targetKey = SMCFanKey.key(SMCFanKey.target, fan: i)
            guard smc.writeKey(targetKey, bytes: floatToSMCBytes(maxRPM)) else {
                throw SmartFanError.writeFailed(targetKey)
            }
            log("Set fan \(i) to max (\(Int(maxRPM)) RPM)")
        }
    }

    /// Set a single fan to a specific RPM
    public func setSpeed(fan index: Int, rpm: Float) throws {
        try Self.validateRPM(rpm)
        let info = try fanInfo(index)

        // Safety: never below minimum
        if info.minRPM > 0 && rpm < info.minRPM {
            throw SmartFanError.rpmOutOfRange(
                requested: rpm, min: info.minRPM, max: info.maxRPM
            )
        }

        // Safety: never above maximum
        if info.maxRPM > 0 && rpm > info.maxRPM {
            throw SmartFanError.rpmOutOfRange(
                requested: rpm, min: info.minRPM, max: info.maxRPM
            )
        }

        if info.mode != "manual" {
            try unlockSingleFan(index)
        }

        let targetKey = SMCFanKey.key(SMCFanKey.target, fan: index)
        guard smc.writeKey(targetKey, bytes: floatToSMCBytes(rpm)) else {
            throw SmartFanError.writeFailed(targetKey)
        }
        log("Set fan \(index) to \(Int(rpm)) RPM")
    }

    /// Resolve each fan independently; fan 0's limits do not constrain other fans.
    func allFanTargets(rpm: Float) throws -> [(index: Int, rpm: Float)] {
        try Self.validateRPM(rpm)
        let count = try fanCount()
        guard count > 0 else { throw SmartFanError.invalidFanIndex(index: 0, count: count) }
        return try (0..<count).map { i in
            let limits = try fanInfo(i)
            var target = rpm
            if limits.maxRPM > 0 { target = min(target, limits.maxRPM) }
            if limits.minRPM > 0 { target = max(target, limits.minRPM) }
            return (i, target)
        }
    }

    /// Set all fans, clamping independently, and return the targets actually written.
    @discardableResult
    public func setAllFans(rpm: Float) throws -> [FanRPM] {
        let targets = try allFanTargets(rpm: rpm)
        try unlockFans(count: targets.count)
        for target in targets {
            let targetKey = SMCFanKey.key(SMCFanKey.target, fan: target.index)
            guard smc.writeKey(targetKey, bytes: floatToSMCBytes(target.rpm)) else {
                throw SmartFanError.writeFailed(targetKey)
            }
            log("Set fan \(target.index) to \(Int(target.rpm)) RPM")
        }
        return targets.map { FanRPM(index: $0.index, rpm: Int($0.rpm)) }
    }

    // MARK: - Reset

    /// Reset all fans to Apple defaults (auto mode, thermalmonitord resumes)
    public func resetAuto() throws {
        let count = try fanCount()
        try FanHandoff.release(
            indices: Array(0..<count), hasFtst: hasFtst,
            modeKey: { SMCFanKey.key(self.modeKeyTemplate, fan: $0) },
            read: {
                let result = self.smc.readKey($0)
                return result.success && result.size == 1 ? result.bytes.first : nil
            },
            write: { self.smc.writeKey($0, bytes: $1) }
        )
        log("Reset to Apple defaults")
    }

    // MARK: - Thermal Sensor Keys

    /// All thermal sensor keys probed for `status()`. Keys absent on a given machine
    /// return nil from `readTemp` and are skipped. Single source of truth so the
    /// daemon's safety floor reads exactly the CPU/GPU subset `status()` would.
    public static let thermalKeys: [String] = [
        // CPU — aggregate (M5 Max verified)
        "TCDX", "TCHP", "TCMb",
        // CPU — per-core (Tp prefix, present across M1-M5 with varying mappings)
        "Tp01", "Tp02", "Tp03", "Tp04", "Tp05", "Tp06", "Tp07", "Tp08",
        "Tp09", "Tp0A", "Tp0B", "Tp0C", "Tp0D", "Tp0F", "Tp0G", "Tp0H",
        "Tp0J", "Tp0L", "Tp0P", "Tp0S", "Tp0T", "Tp0W", "Tp0X", "Tp0b",
        // CPU — M4 generation per-core keys not listed above (Stats' M4 map)
        "Tp0V", "Tp0Y", "Tp0e", "Te05", "Te0S", "Te09", "Te0H",
        // GPU (flt — M1-M4, and ioft 8-byte — M5 Max)
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
        "TG0B", "TG0H", "TG0V",
        // Memory
        "Tm02", "Tm06", "Tm08", "Tm09", "TRDX", "TMVR",
        // Power delivery
        "TPDX",
        // SSD
        "TH0x", "TH0A", "TH0B",
        // Ambient
        "TAOL", "TA0P",
        // Proximity
        "TS0P",
        // Battery
        "TB0T",
    ]

    /// The CPU (TC/Tp) and GPU (TG/Tg) subset the thermal safety floor watches —
    /// derived from `thermalKeys` so it can't drift from what `status()` reports, and
    /// from `SensorRole` so the key list and the sensor catalogue agree on what drives
    /// the fan logic (the `Te*` efficiency cores are deliberately not watched: upstream's
    /// list, kept as is because changing it moves every tuned threshold at once).
    public static var safetyTempKeys: [String] {
        thermalKeys.filter(SensorRole.isControlBasis)
    }

    /// Read one temperature key, decoding by returned size (flt 4-byte or ioft 8-byte).
    /// nil if absent, wrong size, or out of the sane 0–150°C range. Does NOT lock — the
    /// caller serializes SMC access (the daemon takes smcLock per key so a full sweep
    /// never blocks a client write for more than a single read).
    public func readTemp(_ key: String) -> Float? {
        guard let temp = readRawTemp(key) else { return nil }
        guard SMCSensorFilter.accepts(key, temp) else { return nil }
        return temp
    }

    /// Decode one temperature key and sanity-check its 0-150°C range, WITHOUT the
    /// battery rejection filter. `readTemp` wraps this with the filter; the battery
    /// ("feels-like") metric calls it directly, because battery sensors are exactly
    /// what `readTemp` rejects.
    /// What one raw read produced, before `SMCSensorFilter` has its say. The distinction
    /// matters to the preferences' sensor list, which shows a dropped reading and why;
    /// `readRawTemp` collapses it to the usable value alone.
    enum RawSensorRead: Equatable {
        case value(Float)
        /// The key read, but outside the sane 0–150 °C range: a placeholder or junk.
        case outOfRange(Float)
        /// No such key on this Mac, or a size this decoder does not handle.
        case unreadable
    }

    func readRawSensor(_ key: String) -> RawSensorRead {
        let result = smc.readKey(key)
        guard result.success else { return .unreadable }
        let temp: Float
        if result.size == 4 {
            temp = smcBytesToFloat(result.bytes, size: result.size)
        } else if result.size == 8 {
            temp = ioftBytesToFloat(result.bytes)
        } else {
            return .unreadable
        }
        guard temp > 0, temp < 150 else { return .outOfRange(temp) }
        return .value((temp * 10).rounded() / 10)
    }

    func readRawTemp(_ key: String) -> Float? {
        if case .value(let temp) = readRawSensor(key) { return temp }
        return nil
    }

    /// Battery temperature keys read for the "feels-like" metric. `TB0T` is the
    /// classic key; `TB1T`/`TB2T` appear alongside it on some machines.
    static let batteryTempKeys = ["TB0T", "TB1T", "TB2T"]

    /// Average of the battery sensors that read, using the key list plus whatever
    /// `SMCSensorFilter` identified as battery via IOHID. nil when none read, so a
    /// machine without battery sensors reports no feels-like temperature rather than 0.
    func readBatteryTemp() -> Float? {
        var keys = Self.batteryTempKeys
        keys.append(contentsOf: SMCSensorFilter.batteryKeys.filter { !keys.contains($0) })
        var values: [Float] = []
        for key in keys {
            if let t = readRawTemp(key) { values.append(t) }
        }
        guard !values.isEmpty else { return nil }
        return ((values.reduce(0, +) / Float(values.count)) * 10).rounded() / 10
    }

    // MARK: - Status

    /// Read current fan speeds and temperatures
    public func status() throws -> ThermalStatus {
        let count = try fanCount()
        var fans: [ThermalStatus.FanStatus] = []
        var actualReadings: [Float] = []

        for i in 0..<count {
            let (info, actual) = try readFanInfo(i)
            fans.append(ThermalStatus.FanStatus(
                index: i,
                actualRPM: Int(info.actualRPM),
                targetRPM: Int(info.targetRPM),
                minRPM: Int(info.minRPM),
                maxRPM: Int(info.maxRPM),
                mode: info.mode
            ))
            // Only a successful `F{i}Ac` read joins the menu bar average, so a failed
            // read is omitted rather than counted as a stopped fan.
            if let actual { actualReadings.append(actual) }
        }

        // Probe temperature keys across all known Apple Silicon generations.
        // Keys that don't exist on a given machine are skipped automatically.
        // Labels use the raw SMC key name — no assumptions about what a key
        // means on hardware we haven't verified.
        // Probe every known thermal key (flt/ioft decoded by size in readTemp). Keys
        // that don't exist on this machine return nil and are skipped.
        // Every probed key is accounted for, not just the ones that survive: the
        // preferences' sensor list has to show a dropped reading and say why, and the CLI's
        // `discover` shows the raw SMC. The two disagreeing without a reason is exactly what
        // makes a sensor list untrustworthy. No extra SMC traffic: this is the same read
        // `readTemp` already made.
        var temps: [String: Float] = [:]
        var raw: [String: Float] = [:]
        var drops: [String: SensorDrop] = [:]
        for key in Self.thermalKeys {
            switch readRawSensor(key) {
            case .unreadable:
                continue                       // absent on this Mac: nothing to show or drop
            case .outOfRange(let value):
                raw[key] = value
                drops[key] = .outOfRange(value)
            case .value(let value):
                raw[key] = value
                if let rejection = SMCSensorFilter.rejection(key, value) {
                    drops[key] = rejection == .batteryKey ? .batteryKey : .belowDieFloor
                } else {
                    temps[key] = value
                }
            }
        }

        let averageTemp = temps.isEmpty ? nil : temps.values.reduce(0, +) / Float(temps.count)
        let fanRPM = actualReadings.isEmpty ? nil : actualReadings.reduce(0, +) / Float(actualReadings.count)

        return ThermalStatus(fans: fans, temperatures: temps,
                             averageTemp: averageTemp,
                             batteryTemp: readBatteryTemp(),
                             fanRPM: fanRPM,
                             rawTemperatures: raw, sensorDrops: drops)
    }

    // MARK: - Discover

    /// Enumerate SMC keys. Optional prefix filter skips reads for non-matching keys.
    public func discover(prefix: String? = nil) -> [DiscoveredKey] {
        let count = smc.getKeyCount()
        var keys: [DiscoveredKey] = []

        for i: UInt32 in 0..<count {
            guard let keyName = smc.getKeyAtIndex(i) else { continue }

            // Skip non-matching keys early
            if let prefix = prefix, !keyName.hasPrefix(prefix) { continue }

            let info = smc.getKeyInfo(keyName)
            let result = smc.readKey(keyName)

            keys.append(DiscoveredKey(
                key: keyName,
                size: info?.size ?? 0,
                type: info?.type ?? "????",
                bytes: result.success ? result.bytes : []
            ))
        }

        return keys
    }

    // MARK: - Hardware Info

    /// Returns detected hardware capabilities
    public var hardwareInfo: String {
        let ftst = hasFtst ? "yes (M1-M4 path)" : "no (M5+ direct mode)"
        let modeKey = modeKeyTemplate == SMCFanKey.modeLower ? "F%dmd (lowercase)" : "F%dMd (uppercase)"
        return "Ftst unlock: \(ftst), Mode key: \(modeKey)"
    }

    // MARK: - Private Helpers

    private func readFanFloat(_ fan: Int, template: String) -> Float? {
        let key = SMCFanKey.key(template, fan: fan)
        let result = smc.readKey(key)
        guard result.success else { return nil }
        return smcBytesToFloat(result.bytes, size: result.size)
    }

    private func log(_ message: String) {
        logger?.fan(message)
    }
}
