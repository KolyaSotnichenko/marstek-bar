import Foundation
import Testing
@testable import MarstekKit

@Suite struct ForecastTests {
    @Test func dischargeMockupExample() {
        let result = Forecast.estimate(storedWh: 3276.8, ratedWh: 5120, netPowerW: -420, dodPercent: 88)
        guard case .untilEmpty(let t) = result else { Issue.record("expected untilEmpty, got \(result)"); return }
        #expect(formatDuration(t) == "≈ 6 год 20 хв")
    }

    @Test func chargeExample() {
        let result = Forecast.estimate(storedWh: 3276.8, ratedWh: 5120, netPowerW: 1050, dodPercent: 88)
        guard case .untilFull(let t) = result else { Issue.record("expected untilFull, got \(result)"); return }
        #expect(formatDuration(t) == "≈ 1 год 45 хв")
    }

    @Test func belowReserveIsZero() {
        let result = Forecast.estimate(storedWh: 500, ratedWh: 5120, netPowerW: -420, dodPercent: 88)
        #expect(result == .untilEmpty(0))
        #expect(formatDuration(0) == "< 5 хв")
    }

    @Test func idleUnderThreshold() {
        #expect(Forecast.estimate(storedWh: 3000, ratedWh: 5120, netPowerW: 8, dodPercent: 88) == .idle)
        #expect(Forecast.estimate(storedWh: 3000, ratedWh: 5120, netPowerW: -9.9, dodPercent: 88) == .idle)
    }

    @Test func formatsWholeHoursMinutesAndCap() {
        #expect(formatDuration(2 * 3600) == "≈ 2 год")
        #expect(formatDuration(45 * 60) == "≈ 45 хв")
        #expect(formatDuration(150 * 3600) == "> 99 год")
    }

    @Test func smootherDampsSpike() {
        var smoother = PowerSmoother()
        var t = Date(timeIntervalSince1970: 0)
        for _ in 0..<40 { _ = smoother.add(400, at: t); t += 15 }
        #expect(smoother.add(2000, at: t) < 500)
    }

    @Test func smootherResetsOnSignChange() {
        var smoother = PowerSmoother()
        let t = Date(timeIntervalSince1970: 0)
        _ = smoother.add(-400, at: t)
        #expect(smoother.add(1000, at: t + 15) == 1000)
    }
}
