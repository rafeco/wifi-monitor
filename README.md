# WiFi Monitor

A macOS SwiftUI app that tracks WiFi connectivity, signal quality, and router telemetry throughout the day.

Built to answer the question: "Is the WiFi actually going down, or does it just feel that way?"

## Install

Download `WiFiMonitor.zip` from the [latest release](https://github.com/rafeco/wifi-monitor/releases/latest), unzip, and drag to Applications.

Requires macOS 14+.

## What it does

Everything is displayed on a single scrollable page:

**Connectivity** — Pings `1.1.1.1` every 30 seconds and charts latency over a 24-hour timeline. Detects which ISP you're connected to (via [ipinfo.io](https://ipinfo.io)) and color-codes the chart when your connection switches providers.

**WiFi Signal** — Monitors WiFi signal strength (RSSI), noise floor, SNR, transmit rate, channel, and band via CoreWLAN every 30 seconds. Charts RSSI over time with color-coded quality zones (green/yellow/red).

**Router** (optional) — Queries an ASUS router's HTTP API every 60 seconds for WAN status, CPU/memory usage, and bandwidth counters. Shows live performance charts and logs provider switch events. Can be disabled in Settings for machines that don't need it.

**Status bar** — Shows current ping latency, ISP provider, WiFi signal strength, average latency, and uptime percentage at a glance.

## Router setup

Router monitoring is optional. To enable it:

1. Press **Cmd+,** to open Settings
2. Toggle "Enable router monitoring" on
3. Enter your router's IP address (default: `192.168.50.1`), admin username, and password
4. Click "Test Connection" to verify

Currently supports ASUS routers running ASUSWRT firmware (tested with RT-AX58U / RT-AX3000). See [docs/router-api.md](docs/router-api.md) for API details.

## Building from source

```bash
swift build
swift run WiFiMonitor
```

Or open in Xcode: `open Package.swift`

Releases are built automatically by GitHub Actions when a tag is pushed (`git tag v1.2 && git push --tags`).

## Data storage

All data is stored as JSON files in `~/Library/Application Support/WiFiMonitor/`:

```
WiFiMonitor/
├── 2026-04-03.json                  # Ping records (one file per day)
├── wifi/
│   └── wifi-2026-04-03.json         # WiFi signal snapshots
└── router/
    ├── snapshots-2026-04-03.json    # Router CPU/memory/bandwidth snapshots
    └── events-2026-04-03.json       # Provider switch events
```

## Architecture

```
Sources/WiFiMonitor/
├── WiFiMonitorApp.swift              # App entry point, dependency wiring
├── Models/
│   └── PingRecord.swift              # Ping data model + shortConnectionName helper
├── Services/
│   ├── PingService.swift             # 30s ping timer + ISP detection via ipinfo.io
│   ├── PingStore.swift               # JSON persistence for ping data
│   ├── WiFiService.swift             # 30s WiFi signal sampling via CoreWLAN
│   ├── RouterService.swift           # ASUS router HTTP API client + 60s polling
│   └── RouterStore.swift             # JSON persistence for router data
├── Views/
│   ├── ContentView.swift             # Single scrollable page layout
│   ├── LatencyChartView.swift        # Swift Charts latency timeline (5-min buckets)
│   ├── WiFiSignalChartView.swift     # Swift Charts RSSI timeline with quality zones
│   ├── StatusBarView.swift           # Current ping + signal + uptime stats
│   ├── RouterView.swift              # Router dashboard cards and charts
│   └── SettingsView.swift            # Router config + enable/disable toggle
└── Utilities/
    └── DateHelpers.swift             # Day boundary helpers
```

## License

MIT
