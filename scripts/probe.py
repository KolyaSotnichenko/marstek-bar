#!/usr/bin/env python3
"""Read-only probe of a Marstek battery over the local UDP API.

Prints one CSV line per cycle so sign conventions and counters can be
observed while the battery charges or discharges.
"""
import argparse
import json
import socket
import time

FIELDS = ["soc", "bat_capacity", "ongrid_power", "offgrid_power",
          "total_grid_input_energy", "total_grid_output_energy", "bat_temp"]


def call(sock, ip, port, req_id, method, timeout=3.0):
    sock.sendto(json.dumps({"id": req_id, "method": method, "params": {"id": 0}}).encode(), (ip, port))
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock.settimeout(max(0.05, deadline - time.time()))
        try:
            data, _ = sock.recvfrom(8192)
        except socket.timeout:
            break
        try:
            reply = json.loads(data)
        except ValueError:
            continue
        if reply.get("id") == req_id:
            return reply.get("result")
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ip", required=True, help="battery IP address")
    p.add_argument("--port", type=int, default=30000)
    p.add_argument("--minutes", type=float, default=1)
    p.add_argument("--ephemeral", action="store_true", help="send from an unbound port")
    args = p.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if not args.ephemeral:
        sock.bind(("", args.port))

    print("time," + ",".join(FIELDS))
    req_id, answered, asked = 0, 0, 0
    end = time.time() + args.minutes * 60
    while time.time() < end:
        started = time.time()
        row = {}
        for method in ("ES.GetStatus", "Bat.GetStatus"):
            req_id += 1
            asked += 1
            result = call(sock, args.ip, args.port, req_id, method)
            if result is not None:
                answered += 1
                for k, v in result.items():
                    row.setdefault(k, v)
            time.sleep(1.5)
        print(time.strftime("%H:%M:%S") + "," + ",".join(str(row.get(f, "")) for f in FIELDS), flush=True)
        time.sleep(max(0, 10 - (time.time() - started)))
    print(f"# answered {answered}/{asked} ({'ephemeral' if args.ephemeral else 'bound'} port)")


if __name__ == "__main__":
    main()
