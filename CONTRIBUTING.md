# Contributing

Thanks for helping! Bug reports, device reports and pull requests are all welcome.

## Ground rules

- **Read-only.** MarstekBar must never send a command that changes the battery
  (`ES.SetMode`, `DOD.SET`, `Led.Ctrl`, `Ble.Adv`, `Set.Ver`, `Reset.Factory`).
  Pull requests that add one won't be merged. CI checks for these names.
- **Logic goes in `MarstekKit` with a test.** Views only lay out strings that
  `DashboardModel` already computed. All user-facing text lives in `L10n.swift`,
  in both Ukrainian and English.
- Keep requests gentle: one in flight, ≥ 1.5 s apart. Batteries drop UDP replies
  under load.

## Setup

See *Install* in the README for the Xcode project. For the core package alone:

```sh
cd MarstekKit && swift test
```

## Reporting a device

Different Venus models and firmware versions report slightly different fields.
If yours behaves differently, run the read-only probe and attach its output to an
issue (it prints only power, SOC, counters and temperature):

```sh
python3 scripts/probe.py --ip <battery-ip> --minutes 3
```

Please mention the model and firmware (`ver` from `swift run marstek-cli`), and
whether the battery was charging, discharging or idle.
