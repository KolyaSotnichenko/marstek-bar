import Foundation
import Testing
@testable import MarstekKit

var kyiv: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    return c
}

/// 2026-10-28 at the given Kyiv wall-clock time, shifted by `dayOffset` days.
func kyivDate(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
    kyiv.date(from: DateComponents(year: 2026, month: 10, day: 28 + dayOffset, hour: hour, minute: minute))!
}

@Suite struct DailyCountersTests {
    @Test func todayDelta() {
        var d = DailyCounters()
        d.update(chargeWh: 9880, dischargeWh: 3473, at: kyivDate(0, 5), calendar: kyiv)
        d.update(chargeWh: 11980, dischargeWh: 5273, at: kyivDate(14, 0), calendar: kyiv)
        #expect(d.todayChargedWh == 2100)
        #expect(d.todayDischargedWh == 1800)
    }

    @Test func newDayResetsBaseline() {
        var d = DailyCounters()
        d.update(chargeWh: 9000, dischargeWh: 3000, at: kyivDate(23, 50, dayOffset: -1), calendar: kyiv)
        d.update(chargeWh: 9500, dischargeWh: 3100, at: kyivDate(8, 0), calendar: kyiv)
        #expect(d.todayChargedWh == 0)
        d.update(chargeWh: 9700, dischargeWh: 3100, at: kyivDate(14, 0), calendar: kyiv)
        #expect(d.todayChargedWh == 200)
    }

    @Test func counterResetNeverNegative() {
        var d = DailyCounters()
        d.update(chargeWh: 9880, dischargeWh: 3473, at: kyivDate(9, 0), calendar: kyiv)
        d.update(chargeWh: 100, dischargeWh: 10, at: kyivDate(10, 0), calendar: kyiv)
        #expect(d.todayChargedWh >= 0)
        #expect(d.todayDischargedWh >= 0)
        d.update(chargeWh: 150, dischargeWh: 10, at: kyivDate(11, 0), calendar: kyiv)
        #expect(d.todayChargedWh == 50)
    }

    @Test func singleGlitchToZeroIsIgnored() {
        var d = DailyCounters()
        d.update(chargeWh: 9800, dischargeWh: 3000, at: kyivDate(9, 0), calendar: kyiv)
        d.update(chargeWh: 9880, dischargeWh: 3000, at: kyivDate(10, 0), calendar: kyiv)
        d.update(chargeWh: 0, dischargeWh: 3000, at: kyivDate(10, 1), calendar: kyiv)
        d.update(chargeWh: 9890, dischargeWh: 3000, at: kyivDate(10, 2), calendar: kyiv)
        #expect(d.todayChargedWh == 90)
    }

    @Test func realResetKeepsEnergyCountedBefore() {
        var d = DailyCounters()
        d.update(chargeWh: 9800, dischargeWh: 3000, at: kyivDate(9, 0), calendar: kyiv)
        d.update(chargeWh: 9880, dischargeWh: 3000, at: kyivDate(10, 0), calendar: kyiv)
        d.update(chargeWh: 100, dischargeWh: 3000, at: kyivDate(11, 0), calendar: kyiv)
        d.update(chargeWh: 150, dischargeWh: 3000, at: kyivDate(12, 0), calendar: kyiv)
        #expect(d.todayChargedWh == 80 + 50)
    }

    @Test func missingCounterKeepsPrevious() {
        var d = DailyCounters()
        d.update(chargeWh: 9880, dischargeWh: 3473, at: kyivDate(9, 0), calendar: kyiv)
        d.update(chargeWh: 9980, dischargeWh: 3473, at: kyivDate(10, 0), calendar: kyiv)
        d.update(chargeWh: nil, dischargeWh: nil, at: kyivDate(11, 0), calendar: kyiv)
        #expect(d.todayChargedWh == 100)
    }
}

@Suite struct HistoryTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func historyThrottles() {
        var h = HistoryStore()
        for i in 0...6 { h.append(HistorySample(t: t0 + Double(i) * 20, soc: 50)) }
        #expect(h.samples.map(\.t) == [t0, t0 + 60, t0 + 120])
    }

    @Test func historyPrunes7Days() {
        var h = HistoryStore()
        h.append(HistorySample(t: t0 - 8 * 86400, soc: 40))
        h.append(HistorySample(t: t0 - 6 * 86400, soc: 45))
        h.append(HistorySample(t: t0, soc: 50))
        #expect(h.samples.map(\.soc) == [45, 50])
    }

    @Test func seriesSplitsOnGap() {
        var h = HistoryStore()
        for m in 0...10 { h.append(HistorySample(t: t0 + Double(m) * 60, soc: 50)) }
        for m in 40...50 { h.append(HistorySample(t: t0 + Double(m) * 60, soc: 60)) }
        let segments = h.series(endingAt: t0 + 50 * 60)
        #expect(segments.count == 2)
        #expect(segments[0].count == 11)
        #expect(segments[1].first?.soc == 60)
    }

    @Test func seriesCoversOnlyLast24h() {
        var h = HistoryStore()
        h.append(HistorySample(t: t0 - 2 * 86400, soc: 10))
        h.append(HistorySample(t: t0 - 3600, soc: 20))
        #expect(h.series(endingAt: t0).flatMap { $0 }.map(\.soc) == [20])
    }

    @Test func staleAfterFiveMinutes() {
        let s = BatterySnapshot.normalize(es: nil, bat: nil, mode: nil, invertSign: false, at: t0)
        #expect(!s.isStale(now: t0 + 299))
        #expect(s.isStale(now: t0 + 301))
    }
}
