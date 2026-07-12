# WiFi Monitor

A macOS app that tracks WiFi connectivity, signal quality, and router telemetry throughout the day — built to answer: "Is the WiFi actually going down, or does it just feel that way?"

**It runs on any network, but it's built for [ASUS AiMesh](https://www.asus.com/content/asus-aimesh/).** On any Mac you get ping/latency history, ISP detection, WiFi signal charts, and an at-a-glance network "feels like" rating. Point it at an ASUS router and the fine-grained features light up: live router telemetry (CPU, memory, bandwidth), bufferbloat detection, and — on a mesh — showing exactly **which node you're connected to** as you move around the house.

## Install

Download `WiFiMonitor.zip` from the [latest release](https://github.com/rafeco/wifi-monitor/releases/latest), unzip, and drag **WiFiMonitor.app** to your Applications folder.

Releases are signed with an Apple Developer ID and notarized, so if you just want to use the app you can download a release and run it — it opens normally, with no "unidentified developer" warning or right-click-to-open workaround, and no need to build from source.

Requires macOS 14 (Sonoma) or later.

### On first launch: Location permission

macOS will ask for **Location** access. WiFi Monitor uses it only to read the name of the WiFi network you're on — on macOS 14+, reading the network name (SSID) requires Location permission. It's used to label your data by network, detect when you switch networks, and know which router to monitor.

If you deny it, ping/latency and signal monitoring still work, but the network name and per-network router monitoring won't. Nothing is ever sent anywhere — the app makes no use of your actual geographic location.

## What it does

Everything is displayed on a single scrollable page:

**Connectivity** — Pings `1.1.1.1` every 30 seconds and charts latency over a 24-hour timeline. Detects which ISP you're connected to (via [ipinfo.io](https://ipinfo.io)) and color-codes the chart when your connection switches providers.

**WiFi Signal** — Monitors WiFi signal strength (RSSI), noise floor, SNR, transmit rate, channel, and band via CoreWLAN every 30 seconds. Charts RSSI over time with color-coded quality zones (green/yellow/red).

**Network health ("feels like")** — A single at-a-glance rating (Smooth / Usable / Rough / Down) that blends recent latency, jitter, and packet loss — the things that actually make a connection feel bad. When it dips, it tells you *why*: a weak WiFi signal, an upstream/ISP problem, or bufferbloat (your own traffic saturating the link — bufferbloat detection uses ASUS router bandwidth counters).

**Router** (ASUS only) — Queries a supported ASUS router's HTTP API every 60 seconds for WAN status, CPU/memory usage, and bandwidth counters, with live performance charts and a provider-switch log. Configured per network (see below).

**AiMesh node** (ASUS mesh only) — Shows which mesh node you're connected to (e.g. "Living Room"), updating as you roam between nodes. Uses the router's own client-to-node mapping, so no guesswork.

**Status bar** — Shows current ping latency, ISP provider, WiFi network name, band (2.4/5/6 GHz), signal strength, and — on a mesh — the connected node, plus the prominent "feels like" weather rating and uptime percentage.

## Router setup (ASUS only)

Router monitoring is optional and works **only with ASUS routers running ASUSWRT firmware** (tested with RT-AX58U / RT-AX3000 and a ZenWiFi XT8 AiMesh). Everything else in the app works with any router.

Settings keeps a separate profile for **each WiFi network** you join, so you can monitor your home router and ignore every coffee-shop network automatically:

1. Press **Cmd+,** to open Settings and pick your network from the list (the one you're on is marked "Connected").
2. The app checks whether its router is a supported ASUS model. If it isn't, it just says so — there's nothing to configure, and the rest of the app keeps working.
3. For a supported router, turn on **Monitor this network's router**, confirm the auto-detected router IP (or enter it manually), and your admin username and password.
4. Click **Test Connection** to verify. Passwords are stored in the macOS Keychain.

On an AiMesh, the status bar then shows which node you're currently connected to, updating as you roam. The app only polls the router when you're actually on that network, so it never tries to reach it from elsewhere. See [docs/router-api.md](docs/router-api.md) for API details.

## Building from source

```bash
make run
```

This builds the binary, assembles the `.app` bundle (including the icon), and launches the app. Other targets:

```bash
make build   # build without launching
make clean   # remove build artifacts and app bundle
```

Or open in Xcode: `open Package.swift`

Signed, notarized releases are built automatically by GitHub Actions when a version tag is pushed (`git tag v1.4 && git push --tags`). See [docs/signing.md](docs/signing.md) for the signing/notarization setup and how to produce a signed build locally (`make dist`).

## Data storage

All data is stored as JSON files in `~/Library/Application Support/WiFiMonitor/`:

```
WiFiMonitor/
├── 2026-04-03.json                  # Ping records (one file per day)
├── network-profiles.json            # Per-network router settings (no passwords)
├── wifi/
│   └── wifi-2026-04-03.json         # WiFi signal snapshots
└── router/
    ├── snapshots-2026-04-03.json    # Router CPU/memory/bandwidth snapshots
    └── events-2026-04-03.json       # Provider switch events
```

Router passwords are kept in the macOS Keychain, not in these files.

## Architecture

```
Sources/WiFiMonitor/
├── WiFiMonitorApp.swift              # App entry point, dependency wiring
├── Models/
│   ├── PingRecord.swift              # Ping data model + shortConnectionName helper
│   ├── FeelsLike.swift               # "Feels like" score + cause attribution
│   └── NetworkProfile.swift          # Per-SSID router profiles + store
├── Services/
│   ├── PingService.swift             # 30s ping timer + ISP detection via ipinfo.io
│   ├── PingStore.swift               # JSON persistence for ping data
│   ├── WiFiService.swift             # 30s WiFi + SSID sampling, network-change detection
│   ├── RouterService.swift           # ASUS router HTTP API client + 60s polling + probe + AiMesh node
│   ├── RouterStore.swift             # JSON persistence for router data
│   ├── LocationPermission.swift      # Requests Location access (needed to read SSID)
│   └── Keychain.swift                # Router passwords in the macOS Keychain
├── Views/
│   ├── ContentView.swift             # Single scrollable page layout
│   ├── LatencyChartView.swift        # Swift Charts latency timeline (5-min buckets)
│   ├── WiFiSignalChartView.swift     # Swift Charts RSSI timeline with quality zones
│   ├── StatusBarView.swift           # Current ping + signal + feels-like + uptime
│   ├── RouterView.swift              # Router dashboard cards and charts
│   └── SettingsView.swift            # Per-network list + router config
└── Utilities/
    └── DateHelpers.swift             # Day boundary helpers
```

## License

MIT
