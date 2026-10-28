import Foundation

/// Battery state in app terms, independent of the device's sign conventions.
public struct BatterySnapshot: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var soc: Double?
    public var storedWh: Double?
    public var ratedWh: Double?
    public var tempC: Double?
    /// Positive: charging from the grid. Negative: feeding the home.
    public var gridPowerW: Double?
    /// Load on the battery's own off-grid socket, always ≥ 0.
    public var socketPowerW: Double?
    public var mode: String?
    public var chargeCounterWh: Double?
    public var dischargeCounterWh: Double?

    public static func normalize(es: ESStatus?, bat: BatStatus?, mode: String?,
                                 invertSign: Bool, at date: Date) -> BatterySnapshot {
        // ES.GetStatus answers more reliably, so its SOC is the fresher one.
        let soc = es?.batSoc ?? bat?.soc
        let rated = bat?.ratedCapacity ?? es?.batCap
        var stored = bat?.batCapacity
        if stored == nil, let soc, let cap = es?.batCap { stored = soc / 100 * cap }

        let gridSign: Double = (DeviceConventions.gridChargingIsPositive ? 1 : -1) * (invertSign ? -1 : 1)
        let socketSign: Double = DeviceConventions.socketPowerIsPositive ? 1 : -1
        let input = es?.totalGridInputEnergy
        let output = es?.totalGridOutputEnergy

        return BatterySnapshot(
            timestamp: date,
            soc: soc,
            storedWh: stored,
            ratedWh: rated,
            tempC: bat?.batTemp,
            gridPowerW: es?.ongridPower.map { $0 * gridSign },
            socketPowerW: es?.offgridPower.map { max(0, $0 * socketSign) },
            mode: mode,
            chargeCounterWh: DeviceConventions.inputCounterIsCharge ? input : output,
            dischargeCounterWh: DeviceConventions.inputCounterIsCharge ? output : input
        )
    }
}
