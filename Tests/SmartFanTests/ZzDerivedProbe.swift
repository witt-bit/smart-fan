import Foundation
import Testing
@testable import SmartFanCore

@Suite("probe")
struct ZzDerivedProbe {
    @Test("probe: cores vs the rest of the CPU families")
    func families() throws {
        let s = try FanControl().status()
        let t = s.temperatures
        let cores = ThermalStatus.m4CoreKeys
        let cpuFamily = t.filter { entry in ["TC", "Tp", "Te"].contains { entry.key.hasPrefix($0) } }
            .sorted { $0.key < $1.key }
        let hottestCore = t.filter { cores.contains($0.key) }.values.max() ?? 0
        print("PROBE 键     值      类别   与最热核心差")
        for (key, value) in cpuFamily {
            print(String(format: "PROBE %@ %6.1f  %@  %+6.1f", key as NSString, value,
                         (cores.contains(key) ? "核心" : "派生") as NSString, value - hottestCore))
        }
        print(String(format: "PROBE 最热核心 %.1f | 控制基准 %.1f | 差 %+.1f",
                     hottestCore, s.safetyPeakTemp, s.safetyPeakTemp - hottestCore))
        print("PROBE 核心键 = \(cores.sorted().joined(separator: " "))")
    }
}
