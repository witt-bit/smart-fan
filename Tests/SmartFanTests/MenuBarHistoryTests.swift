import Foundation
import Testing
@testable import SmartFanCore

@Suite("Menu bar history")
struct MenuBarHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func sample(_ seconds: TimeInterval, temp: Float? = 50, rpm: Float? = 2000) -> MenuBarHistory.Sample {
        MenuBarHistory.Sample(time: t0.addingTimeInterval(seconds), temperature: temp, rpm: rpm)
    }

    @Test("Samples closer together than the interval are dropped")
    func intervalIsEnforced() {
        var h = MenuBarHistory()
        h.append(sample(0), interval: 1, window: 60)
        h.append(sample(0.5), interval: 1, window: 60)   // too soon
        h.append(sample(1.0), interval: 1, window: 60)
        #expect(h.samples.map(\.time) == [sample(0).time, sample(1.0).time])
    }

    @Test("Points older than the window are trimmed")
    func windowTrims() {
        var h = MenuBarHistory()
        for i in 0...10 { h.append(sample(Double(i)), interval: 1, window: 5) }
        #expect(h.samples.first?.time == sample(5).time)
        #expect(h.samples.last?.time == sample(10).time)
        #expect(h.samples.count == 6)
    }

    @Test("A gap longer than the window discards the stale run (sleep/wake)")
    func sleepWakeGapResets() {
        var h = MenuBarHistory()
        h.append(sample(0), interval: 1, window: 60)
        h.append(sample(1), interval: 1, window: 60)
        h.append(sample(600), interval: 1, window: 60)   // ten-minute hole
        #expect(h.samples.count == 1)
        #expect(h.samples.first?.time == sample(600).time)
    }

    @Test("Shrinking the window truncates immediately")
    func shrinkTruncates() {
        var h = MenuBarHistory()
        for i in 0...20 { h.append(sample(Double(i)), interval: 1, window: 60) }
        #expect(h.samples.count == 21)
        h.trim(window: 5)
        #expect(h.samples.count == 6)
    }

    @Test("Growing the window keeps what is there; later samples fill it in")
    func growKeeps() {
        var h = MenuBarHistory()
        for i in 0...5 { h.append(sample(Double(i)), interval: 1, window: 10) }
        let before = h.samples
        h.trim(window: 60)
        #expect(h.samples == before)
    }

    @Test("The window is capped, and a non-positive interval clears the buffer")
    func guardsAgainstBadInput() {
        var h = MenuBarHistory()
        for i in 0...300 { h.append(sample(Double(i)), interval: 1, window: 10_000) }
        #expect(h.samples.count == Int(MenuBarHistory.maxWindow) + 1)
        h.append(sample(10_000), interval: 0, window: 60)
        #expect(h.samples.isEmpty)
    }

    @Test("reset clears")
    func resetClears() {
        var h = MenuBarHistory()
        h.append(sample(0), interval: 1, window: 60)
        h.reset()
        #expect(h.samples.isEmpty)
    }
}
