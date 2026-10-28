import Foundation
import MarstekKit

// Talks to a real battery on your network: `swift run marstek-cli [--watch] [ip]`.
// Without an IP it uses the first battery that answers discovery.
setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments.dropFirst()
let watch = args.contains("--watch")

let broadcast = try UDPSocketTransport(broadcast: true)
let devices = await MarstekClient.discover(transport: broadcast, timeout: .seconds(3))
print("discovered:", devices.map { "\($0.device ?? "?") @ \($0.ip ?? "?") fw \($0.ver ?? 0)" })
guard let host = args.first(where: { !$0.hasPrefix("--") }) ?? devices.first?.ip else {
    print("No battery answered. Enable the local API in the Marstek app, or pass its IP.")
    exit(1)
}

if watch {
    let poller = Poller(settings: PollerSettings(host: host, deviceName: devices.first?.device),
                        transport: broadcast, initial: nil,
                        onUpdate: { p in
                            let s = p.snapshot
                            print(s.timestamp.formatted(date: .omitted, time: .standard),
                                  "soc", s.soc ?? .nan, "temp", s.tempC ?? .nan, "stored", s.storedWh ?? .nan,
                                  "grid", s.gridPowerW ?? .nan, "socket", s.socketPowerW ?? .nan,
                                  "net~", p.smoothedNetPowerW ?? .nan, "mode", s.mode ?? "?",
                                  "today", p.today.todayChargedWh, p.today.todayDischargedWh)
                        },
                        onDeviceChange: { print("device changed:", $0.device ?? "?", $0.ip ?? "?") })
    await poller.start()
    while true { try await Task.sleep(for: .seconds(3600)) }
}

let client = MarstekClient(host: host, transport: try UDPSocketTransport())
do {
    let es = try await client.call("ES.GetStatus", as: ESStatus.self)
    print("ES:", "soc", es.batSoc ?? .nan, "ongrid", es.ongridPower ?? .nan, "offgrid", es.offgridPower ?? .nan)
} catch { print("ES.GetStatus failed:", error) }
do {
    let bat = try await client.call("Bat.GetStatus", as: BatStatus.self)
    print("BAT:", "soc", bat.soc ?? .nan, "temp", bat.batTemp ?? .nan, "stored", bat.batCapacity ?? .nan)
} catch { print("Bat.GetStatus failed:", error) }
