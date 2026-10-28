import Foundation
import Testing
@testable import MarstekKit

@Suite struct DashboardModelTests {
    let at = kyivDate(14, 32)

    func payload(soc: Double = 64, stored: Double? = 3276.8, temp: Double? = 27, net: Double? = -420,
                 grid: Double? = -420, takenAt: Date? = nil) -> WidgetPayload {
        var snapshot = BatterySnapshot.normalize(es: nil, bat: nil, mode: "Manual", invertSign: false, at: takenAt ?? at)
        snapshot.soc = soc
        snapshot.storedWh = stored
        snapshot.ratedWh = 5120
        snapshot.tempC = temp
        snapshot.gridPowerW = grid
        snapshot.socketPowerW = 0
        return WidgetPayload(snapshot: snapshot, smoothedNetPowerW: net, today: DailyCounters(),
                             history: HistoryStore(), dodPercent: 88, deviceName: "VenusE 3.0")
    }

    func model(_ p: WidgetPayload?, now: Date? = nil) -> DashboardModel {
        DashboardModel(payload: p, now: now ?? at, calendar: kyiv)
    }

    @Test func mockupDischarge() {
        let m = model(payload())
        #expect(m.socText == "64%")
        #expect(m.socFraction == 0.64)
        #expect(m.storedText == "3.3 kWh")
        #expect(m.title == "Venus E 3.0 · Manual")
        #expect(m.forecastLabel == "Вистачить на")
        #expect(m.forecastText == "≈ 6 год 20 хв")
        #expect(m.tempText == "27 °C")
        #expect(m.flows.home == .active(watts: 420))
        #expect(m.updatedText == "оновлено 14:32")
        #expect(!m.isStale)
        #expect(!m.isEmpty)
    }

    @Test func charging() {
        let m = model(payload(net: 1050, grid: 1050))
        #expect(m.forecastLabel == "До повного")
        #expect(m.forecastText == "≈ 1 год 45 хв")
    }

    @Test func idle() {
        let m = model(payload(net: 0, grid: 0))
        #expect(m.forecastLabel == "Очікування")
        #expect(m.forecastText == "—")
    }

    @Test func staleFlag() {
        let m = model(payload(takenAt: at - 6 * 60))
        #expect(m.isStale)
        #expect(m.updatedText == "оновлено 14:26")
    }

    @Test func emptyPayload() {
        let m = model(nil)
        #expect(m.isEmpty)
        #expect(m.socText == "—")
        #expect(m.forecastText == "—")
    }

    @Test func todayFormatting() throws {
        var p = payload()
        p.today.update(chargeWh: 9000, dischargeWh: 3000, at: kyivDate(0, 5), calendar: kyiv)
        p.today.update(chargeWh: 11100, dischargeWh: 4800, at: kyivDate(14, 0), calendar: kyiv)
        #expect(model(p).todayText == "Сьогодні: ↑ 2.1 kWh · ↓ 1.8 kWh")
    }

    @Test func nullTempShowsDash() {
        #expect(model(payload(temp: nil)).tempText == "— °C")
    }

    @Test func missingStoredHasNoForecast() {
        #expect(model(payload(stored: nil)).forecastText == "—")
    }

    @Test func absurdDeviceValuesDoNotCrash() {
        var p = payload(soc: 1e300, temp: 1e300, net: -1e-300, grid: 1e300)
        p.snapshot.socketPowerW = .infinity
        let m = model(p)
        #expect(m.socText == "—")
        #expect(m.tempText == "— °C")
        #expect(wattsText(1e300) == "—")
        #expect(wattsText(.nan) == "—")
        #expect(formatDuration(.infinity) == "> 99 год")
        #expect(formatDuration(.nan) == "—")
    }

    @Test func watts() {
        #expect(wattsText(420) == "420 W")
        #expect(wattsText(-420) == "420 W")
        #expect(wattsText(-0.0) == "0 W")
        #expect(wattsText(1200) == "1.2 kW")
    }
}
