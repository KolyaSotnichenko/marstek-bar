import Foundation

/// "Today" energy from the battery's lifetime counters. The baseline is the first
/// sample of the local day, so a Mac that was off at midnight never counts yesterday.
public struct DailyCounters: Codable, Equatable, Sendable {
    private var day: Date?
    private var charge = DayCounter()
    private var discharge = DayCounter()

    public init() {}

    public var todayChargedWh: Double { charge.today }
    public var todayDischargedWh: Double { discharge.today }

    public mutating func update(chargeWh: Double?, dischargeWh: Double?, at date: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: date)
        if day != today {
            day = today
            charge = DayCounter()
            discharge = DayCounter()
        }
        if let chargeWh { charge.add(chargeWh) }
        if let dischargeWh { discharge.add(dischargeWh) }
    }
}

/// One lifetime counter within a day. A lower reading is believed only when the
/// next one confirms it: a single glitch (e.g. a 0) is dropped, while a real reset
/// keeps the energy counted before it.
struct DayCounter: Codable, Equatable, Sendable {
    private var baseline: Double?
    private var value: Double?
    private var carried: Double = 0
    private var pendingDrop: Double?

    var today: Double {
        guard let baseline, let value else { return carried }
        return carried + max(0, value - baseline)
    }

    mutating func add(_ reading: Double) {
        guard let current = value else {
            baseline = reading
            value = reading
            return
        }
        guard reading < current else {
            pendingDrop = nil
            value = reading
            return
        }
        guard let firstLow = pendingDrop else {
            pendingDrop = reading
            return
        }
        carried = today
        baseline = firstLow
        value = reading
        pendingDrop = nil
    }
}
