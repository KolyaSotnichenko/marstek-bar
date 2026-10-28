import Foundation
import Testing
@testable import MarstekKit

@Suite struct PowerFlowTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    /// Raw `ongrid_power` that means "charging at `watts`" under the device convention.
    func rawCharging(_ watts: Double) -> Double { DeviceConventions.gridChargingIsPositive ? watts : -watts }

    func snapshot(grid: Double?, socket: Double? = 0) -> BatterySnapshot {
        var s = BatterySnapshot.normalize(es: nil, bat: nil, mode: nil, invertSign: false, at: now)
        s.gridPowerW = grid
        s.socketPowerW = socket
        return s
    }

    @Test func normalizeMissingBatPowerUsesOngrid() {
        let es = ESStatus(ongridPower: rawCharging(1200), batPower: nil)
        #expect(BatterySnapshot.normalize(es: es, bat: nil, mode: nil, invertSign: false, at: now).gridPowerW == 1200)
        #expect(BatterySnapshot.normalize(es: es, bat: nil, mode: nil, invertSign: true, at: now).gridPowerW == -1200)
    }

    @Test func normalizeFallbackStored() {
        let es = ESStatus(batSoc: 64, batCap: 5120)
        let s = BatterySnapshot.normalize(es: es, bat: nil, mode: "Manual", invertSign: false, at: now)
        #expect(s.storedWh == 3276.8)
        #expect(s.ratedWh == 5120)
        #expect(s.soc == 64)
        #expect(s.mode == "Manual")
    }

    @Test func normalizePrefersBatStatus() {
        let es = ESStatus(batSoc: 64, batCap: 5120, totalGridOutputEnergy: 3473, totalGridInputEnergy: 9893)
        let bat = BatStatus(soc: 65, batTemp: 27, batCapacity: 3300, ratedCapacity: 5100)
        let s = BatterySnapshot.normalize(es: es, bat: bat, mode: nil, invertSign: false, at: now)
        #expect(s.storedWh == 3300)
        #expect(s.ratedWh == 5100)
        #expect(s.tempC == 27)
        #expect(s.chargeCounterWh == 9893)
        #expect(s.dischargeCounterWh == 3473)
    }

    @Test func socketPowerNeverNegative() {
        let es = ESStatus(offgridPower: DeviceConventions.socketPowerIsPositive ? -5 : 5)
        #expect(BatterySnapshot.normalize(es: es, bat: nil, mode: nil, invertSign: false, at: now).socketPowerW == 0)
    }

    @Test func flowsBothActive() {
        let flows = PowerFlows.from(snapshot(grid: 1200, socket: 150))
        #expect(flows.grid == .active(watts: 1200))
        #expect(flows.socket == .active(watts: 150))
        #expect(flows.home == .idle)
    }

    @Test func flowsDischarge() {
        let flows = PowerFlows.from(snapshot(grid: -420))
        #expect(flows.home == .active(watts: 420))
        #expect(flows.grid == .idle)
        #expect(flows.socket == .idle)
    }

    @Test func flowsIdleUnderThresholdAndUnknown() {
        #expect(PowerFlows.from(snapshot(grid: 9, socket: 3)) == PowerFlows(grid: .idle, home: .idle, socket: .idle))
        #expect(PowerFlows.from(snapshot(grid: nil, socket: nil)) == PowerFlows(grid: .idle, home: .idle, socket: .idle))
    }

    @Test func netPower() {
        #expect(netBatteryPowerW(gridPowerW: 1200, socketPowerW: 150) == 1050)
        #expect(netBatteryPowerW(gridPowerW: -420, socketPowerW: 0) == -420)
    }
}
