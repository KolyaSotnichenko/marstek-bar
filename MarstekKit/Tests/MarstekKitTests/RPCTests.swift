import Foundation
import Testing
@testable import MarstekKit

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct RPCTests {
    @Test func decodesRealESStatus() throws {
        let reply = try RPC.decode(fixture("es_status"), as: ESStatus.self)
        let es = try #require(reply.result)
        #expect(es.batSoc == 100)
        #expect(es.batCap == 5120)
        #expect(es.totalGridInputEnergy == 9893)
        #expect(es.batPower == nil)
        #expect(reply.src == "VenusE 3.0-a1b2c3d4e5f6")
    }

    @Test func decodesRealBatStatus() throws {
        let bat = try #require(try RPC.decode(fixture("bat_status"), as: BatStatus.self).result)
        #expect(bat.soc == 100)
        #expect(bat.batTemp == 25.0)
        #expect(bat.ratedCapacity == 5120)
    }

    @Test func decodesNullFields() throws {
        let data = Data(#"{"id":1,"result":{"id":0,"soc":null,"bat_temp":null}}"#.utf8)
        let bat = try #require(try RPC.decode(data, as: BatStatus.self).result)
        #expect(bat.soc == nil)
        #expect(bat.batTemp == nil)
        #expect(bat.batCapacity == nil)
        #expect(bat.chargFlag == nil)
    }

    @Test func decodesSocAsString() throws {
        let data = Data(#"{"id":1,"result":{"soc":"64"}}"#.utf8)
        #expect(try RPC.decode(data, as: BatStatus.self).result?.soc == 64)
    }

    @Test func throwsRPCErrorOnMethodNotFound() throws {
        #expect(throws: RPCError.self) { try RPC.decode(fixture("pv_error"), as: ESStatus.self) }
        do {
            _ = try RPC.decode(fixture("pv_error"), as: ESStatus.self)
        } catch let error as RPCError {
            #expect(error.code == -32601)
        }
    }

    @Test func decodesDeviceInfo() throws {
        let info = try #require(try RPC.decode(fixture("get_device"), as: DeviceInfo.self).result)
        #expect(info.device == "VenusE 3.0")
        #expect(info.ip == "192.168.1.50")
        #expect(info.ver == 150)
    }

    @Test func requestIsValidJSON() throws {
        let data = RPC.request(id: 7, method: "ES.GetStatus", params: ["id": 0])
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["id"] as? Int == 7)
        #expect(obj["method"] as? String == "ES.GetStatus")
        #expect((obj["params"] as? [String: Any])?["id"] as? Int == 0)
    }

    @Test func peekID() throws {
        #expect(RPC.peekID(try fixture("es_status")) == 100)
        #expect(RPC.peekID(Data("garbage".utf8)) == nil)
    }
}
