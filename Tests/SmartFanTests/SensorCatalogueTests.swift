import Foundation
import Testing
@testable import SmartFanCore

@Suite("Sensor catalogue — what each key is and who reads it")
struct SensorCatalogueTests {
    private let table = ThermalStatus.m4CoreKeys

    // MARK: - What the key is

    @Test("A key in the chip's table is a core; the rest of its family is not")
    func kindWithTable() {
        #expect(SensorRole.kind(of: "Tp01", coreKeys: table) == .cpuCore)
        #expect(SensorRole.kind(of: "Te05", coreKeys: table) == .cpuCore)
        // The same group as Tp01, but not the core temperature — and the SoC-level keys.
        #expect(SensorRole.kind(of: "Tp0W", coreKeys: table) == .cpuDerived)
        #expect(SensorRole.kind(of: "Tp02", coreKeys: table) == .cpuDerived)
        #expect(SensorRole.kind(of: "TCMb", coreKeys: table) == .cpuDerived)
        #expect(SensorRole.kind(of: "Te0Z", coreKeys: table) == .cpuDerived)
    }

    @Test("With no table for the chip, the prefix grouping is all there is")
    func kindWithoutTable() {
        for key in ["TC0P", "Tp01", "Te05"] {
            #expect(SensorRole.kind(of: key, coreKeys: []) == .cpuPrefix)
        }
        // The other families do not depend on the table.
        #expect(SensorRole.kind(of: "Tg0L", coreKeys: []) == .gpu)
    }

    @Test("Every other family is recognised by prefix")
    func kinds() {
        let cases: [(String, SensorRole.Kind)] = [
            ("TG0B", .gpu), ("Tg0L", .gpu),
            ("TRDX", .memory), ("Tm02", .memory), ("TMVR", .memory),
            ("TH0x", .ssd), ("TAOL", .ambient), ("TB0T", .battery),
            ("TPDX", .power), ("TS0P", .other),
        ]
        for (key, kind) in cases {
            #expect(SensorRole.kind(of: key, coreKeys: table) == kind, "\(key)")
        }
    }

    // MARK: - Who reads it

    @Test("The CPU row reads cores, not the keys that merely share their prefix")
    func cpuUses() {
        let core = SensorRole.role(of: "Tp01", coreKeys: table)
        #expect(core.uses == [.cpu, .average, .control])
        let derived = SensorRole.role(of: "Tp0W", coreKeys: table)
        #expect(derived.uses == [.average, .control])
        #expect(!derived.uses.contains(.cpu))
    }

    @Test("The fan logic does not watch the efficiency cores")
    func efficiencyCoresAreNotWatched() {
        // Upstream's list omits `Te*`; that is kept, so the CPU row shows them while the
        // ladder and the curves do not compare against them.
        let role = SensorRole.role(of: "Te05", coreKeys: table)
        #expect(role.kind == .cpuCore)
        #expect(role.uses == [.cpu, .average])
        #expect(!SensorRole.isControlBasis("Te05"))
    }

    @Test("Memory, SSD, ambient and battery feed the readings and the average only")
    func peripheralUses() {
        #expect(SensorRole.role(of: "TRDX", coreKeys: table).uses == [.ram, .average])
        #expect(SensorRole.role(of: "TH0x", coreKeys: table).uses == [.ssd, .average])
        #expect(SensorRole.role(of: "TAOL", coreKeys: table).uses == [.ambient, .average])
        #expect(SensorRole.role(of: "TB0T", coreKeys: table).uses == [.feelsLike, .average])
        #expect(SensorRole.role(of: "TPDX", coreKeys: table).uses == [.average])
    }

    @Test("GPU keys feed the GPU row, the average and the fan logic")
    func gpuUses() {
        #expect(SensorRole.role(of: "Tg0L", coreKeys: table).uses == [.gpu, .average, .control])
    }

    // MARK: - The guard that keeps the two key lists from drifting

    @Test("The safety floor watches exactly the keys the catalogue marks for control")
    func safetyKeysMatchTheCatalogue() {
        let watched = Set(FanControl.safetyTempKeys)
        #expect(!watched.isEmpty)
        for key in FanControl.thermalKeys {
            let role = SensorRole.role(of: key, coreKeys: table)
            #expect(watched.contains(key) == role.uses.contains(.control), "\(key)")
        }
        // And the same list still means the same thing it did before it was derived.
        for key in FanControl.thermalKeys {
            #expect(SensorRole.isControlBasis(key)
                    == ["TC", "Tp", "TG", "Tg"].contains { key.hasPrefix($0) }, "\(key)")
        }
    }

    // MARK: - The list itself

    private func status(_ temperatures: [String: Float],
                        raw: [String: Float] = [:],
                        drops: [String: SensorDrop] = [:]) -> ThermalStatus {
        ThermalStatus(fans: [], temperatures: temperatures,
                      rawTemperatures: raw, sensorDrops: drops)
    }

    @Test("Every probed key gets a row, so nothing is silently missing")
    func everyKeyIsListed() {
        let rows = status(["Tp01": 74.1], raw: ["Tp01": 74.1]).sensorReadings(coreKeys: table)
        #expect(rows.count == FanControl.thermalKeys.count)
        #expect(Set(rows.map(\.key)) == Set(FanControl.thermalKeys))
        // A key that read nothing is reported as absent rather than left out.
        let absent = try? #require(rows.first { $0.key == "TCDX" })
        #expect(absent?.drop == .absent)
        #expect(absent?.raw == nil && absent?.accepted == nil)
    }

    @Test("A dropped reading keeps its value and says why")
    func droppedReadingsAreExplained() {
        let rows = status(["Tp01": 74.1],
                          raw: ["Tp01": 74.1, "Tp0W": 91.5, "TA0P": 300.0],
                          drops: ["Tp0W": .belowDieFloor, "TA0P": .outOfRange(300.0)])
            .sensorReadings(coreKeys: table)

        let kept = try? #require(rows.first { $0.key == "Tp01" })
        #expect(kept?.accepted == 74.1 && kept?.raw == 74.1 && kept?.drop == nil)

        let floor = try? #require(rows.first { $0.key == "Tp0W" })
        #expect(floor?.raw == 91.5)
        #expect(floor?.accepted == nil)
        #expect(floor?.drop == .belowDieFloor)
        #expect(floor?.role.kind == .cpuDerived)

        let junk = try? #require(rows.first { $0.key == "TA0P" })
        #expect(junk?.raw == 300.0 && junk?.accepted == nil && junk?.drop == .outOfRange(300.0))
    }

    @Test("Rows are ordered by role and then by key, so the list does not jump")
    func ordering() {
        let rows = status(["Tp01": 74.1, "Tg0L": 60.0, "TAOL": 25.0, "TH0x": 37.0, "TRDX": 41.0],
                          raw: ["Tp01": 74.1, "Tp0W": 91.5, "Tg0L": 60.0, "TAOL": 25.0,
                                "TH0x": 37.0, "TRDX": 41.0],
                          drops: ["Tp0W": .belowDieFloor])
            .sensorReadings(coreKeys: table)

        let order = SensorRole.Kind.allCases
        let indices = rows.map { order.firstIndex(of: $0.role.kind) ?? 0 }
        #expect(indices == indices.sorted())
        for kind in SensorRole.Kind.allCases {
            let keys = rows.filter { $0.role.kind == kind }.map(\.key)
            #expect(keys == keys.sorted())
        }
    }

    // MARK: - The filter's reasons

    @Test("The filter says which rule dropped a reading")
    func rejections() {
        #expect(SMCSensorFilter.rejection("TG0B", 60, batteryKeys: ["TG0B"]) == .batteryKey)
        #expect(SMCSensorFilter.rejection("Tp02", 5, batteryKeys: []) == .belowDieFloor)
        #expect(SMCSensorFilter.rejection("Tg0L", 9.9, batteryKeys: []) == .belowDieFloor)
        // Only the die families have a floor: a cool ambient sensor is a real reading.
        #expect(SMCSensorFilter.rejection("TAOL", 5, batteryKeys: []) == nil)
        #expect(SMCSensorFilter.rejection("Tp01", 10, batteryKeys: []) == nil)
        #expect(SMCSensorFilter.rejection("Tp01", 74.1, batteryKeys: []) == nil)
    }
}

@Suite("Thermal status wire format")
struct ThermalStatusWireTests {
    @Test("The sensor list does not leak into the daemon's status JSON")
    func rawKeysAreNotEncoded() throws {
        let status = ThermalStatus(fans: [], temperatures: ["Tp01": 74.1],
                                   averageTemp: 74.1, batteryTemp: 29.2, fanRPM: 2496,
                                   rawTemperatures: ["Tp01": 74.1, "Tp0W": 91.5],
                                   sensorDrops: ["Tp0W": .belowDieFloor])
        let data = try JSONEncoder().encode(status)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["temperatures"] != nil)
        #expect(json["averageTemp"] != nil)
        #expect(json.keys.contains("rawTemperatures") == false)
        #expect(json.keys.contains("sensorDrops") == false)
    }
}
