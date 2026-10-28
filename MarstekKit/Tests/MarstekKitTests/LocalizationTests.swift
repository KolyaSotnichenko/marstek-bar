import Foundation
import Testing
@testable import MarstekKit

@Suite struct LocalizationTests {
    let at = kyivDate(14, 32)

    func payload(net: Double = -420, takenAt: Date? = nil) -> WidgetPayload {
        var snapshot = BatterySnapshot.normalize(es: nil, bat: nil, mode: "Manual", invertSign: false, at: takenAt ?? at)
        snapshot.soc = 64
        snapshot.storedWh = 3276.8
        snapshot.ratedWh = 5120
        snapshot.tempC = 27
        snapshot.gridPowerW = net
        snapshot.socketPowerW = 0
        var today = DailyCounters()
        today.update(chargeWh: 9000, dischargeWh: 3000, at: kyivDate(0, 5), calendar: kyiv)
        today.update(chargeWh: 11100, dischargeWh: 4800, at: kyivDate(14, 0), calendar: kyiv)
        return WidgetPayload(snapshot: snapshot, smoothedNetPowerW: net, today: today,
                             history: HistoryStore(), dodPercent: 88, deviceName: "VenusE 3.0")
    }

    @Test func englishDashboard() {
        let m = DashboardModel(payload: payload(), now: at, calendar: kyiv, language: .en)
        #expect(m.forecastLabel == "Lasts")
        #expect(m.forecastText == "≈ 6 h 20 min")
        #expect(m.todayText == "Today: ↑ 2.1 kWh · ↓ 1.8 kWh")
        #expect(m.updatedText == "updated 14:32")
        #expect(m.text.grid == "Grid")
        #expect(m.text.socket == "Socket")
    }

    @Test func englishChargingAndIdle() {
        #expect(DashboardModel(payload: payload(net: 1050), now: at, calendar: kyiv, language: .en).forecastLabel == "Until full")
        #expect(DashboardModel(payload: payload(net: 0), now: at, calendar: kyiv, language: .en).forecastLabel == "Idle")
    }

    @Test func englishDurations() {
        #expect(formatDuration(2 * 3600, language: .en) == "≈ 2 h")
        #expect(formatDuration(45 * 60, language: .en) == "≈ 45 min")
        #expect(formatDuration(0, language: .en) == "< 5 min")
        #expect(formatDuration(150 * 3600, language: .en) == "> 99 h")
    }

    @Test func ukrainianStaysDefault() {
        let m = DashboardModel(payload: payload(), now: at, calendar: kyiv)
        #expect(m.forecastLabel == "Вистачить на")
        #expect(m.text.home == "Дім")
    }

    @Test func updatedShowsDateWhenNotToday() {
        let old = payload(takenAt: kyivDate(14, 5, dayOffset: -1))
        #expect(DashboardModel(payload: old, now: at, calendar: kyiv).updatedText == "оновлено 27.10 14:05")
        #expect(DashboardModel(payload: old, now: at, calendar: kyiv, language: .en).updatedText == "updated 27.10 14:05")
    }

    @Test func chartEndsAtModelTime() {
        #expect(DashboardModel(payload: payload(), now: at, calendar: kyiv).chartEnd == at)
    }

    @Test func menuBarTextMarksStaleData() {
        #expect(DashboardModel(payload: payload(), now: at, calendar: kyiv).menuBarText == "64%")
        let stale = DashboardModel(payload: payload(takenAt: at - 600), now: at, calendar: kyiv)
        #expect(stale.menuBarText == "(64%)")
        #expect(DashboardModel(payload: nil, now: at).menuBarText == "—")
    }

    @Test func languageResolvesSystem() {
        #expect(AppLanguage.system.resolved(preferred: ["uk-UA"]) == .uk)
        #expect(AppLanguage.system.resolved(preferred: ["en-GB", "uk-UA"]) == .en)
        #expect(AppLanguage.en.resolved(preferred: ["uk-UA"]) == .en)
    }
}
