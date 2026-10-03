import Foundation
import Testing
@testable import SmartFanCore

@Suite("probe") struct ZzTraceProbe {
    @Test func trace() throws {
        let fc = try FanControl()
        var basis: [Float] = [], cores: [Float] = []
        print("PROBE 采样 60 秒（每 0.5 秒）…")
        for _ in 0..<120 {
            let s = try fc.status()
            basis.append(s.safetyPeakTemp)
            cores.append(s.displayedCPUTemp ?? 0)
            Thread.sleep(forTimeInterval: 0.5)
        }
        func report(_ name: String, _ v: [Float]) {
            let sorted = v.sorted()
            print(String(format: "PROBE %@ 最低%.1f 中位%.1f 最高%.1f", name as NSString,
                         sorted.first!, sorted[sorted.count / 2], sorted.last!))
            // 最长连续 ≥95 / <90 的时长（0.5s 一步）
            func longest(_ test: (Float) -> Bool) -> Double {
                var best = 0.0, run = 0.0
                for x in v { if test(x) { run += 0.5; best = max(best, run) } else { run = 0 } }
                return best
            }
            print(String(format: "PROBE   连续 ≥95 最长 %.1f 秒（升级需要 30 秒）", longest { $0 >= 95 }))
            print(String(format: "PROBE   连续 <90 最长 %.1f 秒（解除需要 30 秒）", longest { $0 < 90 }))
            print(String(format: "PROBE   ≥90 占比 %.0f%%  ≥95 占比 %.0f%%",
                         100 * Double(v.filter { $0 >= 90 }.count) / Double(v.count),
                         100 * Double(v.filter { $0 >= 95 }.count) / Double(v.count)))
        }
        report("控制基准(现在用的)", basis)
        report("真实核心(校准的)", cores)
    }
}
