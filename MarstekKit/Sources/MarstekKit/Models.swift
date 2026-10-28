import Foundation

// Every field may be null or missing (spec), so all of them are optional.

public struct DeviceInfo: Codable, Equatable, Sendable {
    public var device: String?
    public var ver: Int?
    public var bleMac: String?
    public var wifiMac: String?
    public var wifiName: String?
    public var ip: String?
}

public struct ESStatus: Decodable, Equatable, Sendable {
    public var batSoc: Double?
    public var batCap: Double?
    public var pvPower: Double?
    public var ongridPower: Double?
    public var offgridPower: Double?
    /// Missing on Venus E 3.0 firmware 150.
    public var batPower: Double?
    public var totalGridOutputEnergy: Double?
    public var totalGridInputEnergy: Double?

    public init(batSoc: Double? = nil, batCap: Double? = nil, pvPower: Double? = nil,
                ongridPower: Double? = nil, offgridPower: Double? = nil, batPower: Double? = nil,
                totalGridOutputEnergy: Double? = nil, totalGridInputEnergy: Double? = nil) {
        self.batSoc = batSoc
        self.batCap = batCap
        self.pvPower = pvPower
        self.ongridPower = ongridPower
        self.offgridPower = offgridPower
        self.batPower = batPower
        self.totalGridOutputEnergy = totalGridOutputEnergy
        self.totalGridInputEnergy = totalGridInputEnergy
    }
}

public struct BatStatus: Decodable, Equatable, Sendable {
    public var soc: Double?
    public var batTemp: Double?
    public var batCapacity: Double?
    public var ratedCapacity: Double?
    public var chargFlag: Bool?
    public var dischrgFlag: Bool?

    public init(soc: Double? = nil, batTemp: Double? = nil, batCapacity: Double? = nil,
                ratedCapacity: Double? = nil, chargFlag: Bool? = nil, dischrgFlag: Bool? = nil) {
        self.soc = soc
        self.batTemp = batTemp
        self.batCapacity = batCapacity
        self.ratedCapacity = ratedCapacity
        self.chargFlag = chargFlag
        self.dischrgFlag = dischrgFlag
    }

    private enum CodingKeys: String, CodingKey {
        case soc, batTemp, batCapacity, ratedCapacity, chargFlag, dischrgFlag
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The spec types `soc` as a string; the device sends a number.
        if let number = try? c.decodeIfPresent(Double.self, forKey: .soc) {
            soc = number
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .soc) {
            soc = Double(text)
        }
        batTemp = try c.decodeIfPresent(Double.self, forKey: .batTemp)
        batCapacity = try c.decodeIfPresent(Double.self, forKey: .batCapacity)
        ratedCapacity = try c.decodeIfPresent(Double.self, forKey: .ratedCapacity)
        chargFlag = try c.decodeIfPresent(Bool.self, forKey: .chargFlag)
        dischrgFlag = try c.decodeIfPresent(Bool.self, forKey: .dischrgFlag)
    }
}

public struct ESMode: Decodable, Equatable, Sendable {
    public var mode: String?
}
