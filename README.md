# WiFi Monitor

A macOS SwiftUI app that tracks WiFi connectivity quality throughout the day and pulls live telemetry from an ASUS router.

Built to answer the question: "Is the WiFi actually going down, or does it just feel that way?"

## What it does

**Connectivity tab** — Pings `1.1.1.1` every 30 seconds and charts latency over a 24-hour timeline. Detects which ISP you're connected to (via [ipinfo.io](https://ipinfo.io)) and color-codes the chart when your connection switches providers.

**Router tab** — Queries an ASUS router's HTTP API every 60 seconds for WAN status, CPU/memory usage, and bandwidth counters. Shows live performance charts and logs provider switch events.

## Screenshots

_Coming soon_

## Requirements

- macOS 14+
- Swift 5.9+
- An ASUS router running ASUSWRT firmware (tested with RT-AX58U / RT-AX3000)

## Building and running

```bash
swift build
swift run WiFiMonitor
```

Or open in Xcode:

```bash
open Package.swift
```

### Running as an app

To get a proper Dock icon and app experience, create a `.app` bundle:

```bash
swift build
mkdir -p WiFiMonitor.app/Contents/MacOS
cp .build/arm64-apple-macosx/debug/WiFiMonitor WiFiMonitor.app/Contents/MacOS/
```

Then create `WiFiMonitor.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WiFiMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.WiFiMonitor</string>
    <key>CFBundleName</key>
    <string>WiFi Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
</dict>
</plist>
```

Then `open WiFiMonitor.app`.

## Router setup

1. Launch the app
2. Press **Cmd+,** to open Settings
3. Enter your router's IP address (default: `192.168.50.1`), admin username, and password
4. Click "Test Connection" to verify
5. Switch to the Router tab

See [docs/router-api.md](docs/router-api.md) for details on the ASUS router API integration.

## Data storage

All data is stored as JSON files in `~/Library/Application Support/WiFiMonitor/`:

```
WiFiMonitor/
├── 2026-04-03.json              # Ping records (one file per day)
└── router/
    ├── snapshots-2026-04-03.json # Router CPU/memory/bandwidth snapshots
    ├── events-2026-04-03.json    # Provider switch events
    └── debug-response.txt        # Latest raw router API response (for debugging)
```

## Architecture

```
Sources/WiFiMonitor/
├── WiFiMonitorApp.swift              # App entry point, dependency wiring
├── Models/
│   └── PingRecord.swift              # Ping data model (Codable)
├── Services/
│   ├── PingService.swift             # 30s ping timer + ISP detection
│   ├── PingStore.swift               # JSON persistence for ping data
│   ├── RouterService.swift           # ASUS router API client + polling
│   └── RouterStore.swift             # JSON persistence for router data
├── Views/
│   ├── ContentView.swift             # TabView (Connectivity + Router)
│   ├── LatencyChartView.swift        # Swift Charts timeline (5-min buckets)
│   ├── StatusBarView.swift           # Current ping + uptime stats
│   ├── RouterView.swift              # Router dashboard with live charts
│   └── SettingsView.swift            # Router credentials config
└── Utilities/
    └── DateHelpers.swift             # Day boundary helpers
```

## License

MIT
