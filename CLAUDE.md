# CLAUDE.md

## Project overview

WiFi Monitor is a macOS SwiftUI app that monitors WiFi connectivity and ASUS router telemetry. It's a personal utility — not sandboxed, not distributed via the App Store.

## Build and run

```bash
swift build          # Build the package
swift run WiFiMonitor # Run directly (no Dock icon)
```

For a proper macOS app experience, copy the binary into `WiFiMonitor.app/Contents/MacOS/` and `open WiFiMonitor.app`.

## Key design decisions

- **SPM executable, not Xcode project** — `Package.swift` defines everything. No `.xcodeproj`. Can be opened in Xcode via `open Package.swift`.
- **No SwiftData** — SwiftData macros don't work with SPM's command-line build. Uses JSON file persistence instead (`PingStore`, `RouterStore`).
- **No sandbox** — The app shells out to `/sbin/ping` (which is setuid) and `/usr/bin/curl`, and makes HTTP requests to the local router. None of this works in a sandbox.
- **ISP detection via ipinfo.io** — Checks external IP org every 2 minutes via curl. Cached to avoid hammering the API.
- **Router API via URLSession** — Direct HTTP requests to the ASUS router's undocumented `/login.cgi` and `/appGet.cgi` endpoints. Each hook requires a separate HTTP request (combining hooks in one request only returns the first).
- **CPU counters are cumulative** — The router returns cumulative `cpu_total`/`cpu_usage` counters. The service computes deltas between polls to get percentages.
- **Bandwidth from hex counters** — `netdev(appobj)` returns byte counters in hex (e.g., `"INTERNET_rx":"0xd30ad37f8"`). Deltas between polls give bytes/sec.

## File layout

- `Services/` — Background polling and data persistence. `PingService` and `RouterService` are `@Observable` and injected via SwiftUI `.environment()`.
- `Views/` — SwiftUI views. `LatencyChartView` uses Swift Charts with 5-minute bucketing. `RouterView` has bandwidth and performance charts.
- `Models/` — `PingRecord` is the only model. Router types (`WanStatus`, `CpuUsage`, etc.) live in `RouterService.swift`.

## Router credentials

Stored in `UserDefaults` (keys: `routerIP`, `routerUsername`, `routerPassword`). This is a personal app — Keychain would be overkill.

## Data files

All in `~/Library/Application Support/WiFiMonitor/`. Ping data: `YYYY-MM-DD.json`. Router data: `router/snapshots-YYYY-MM-DD.json` and `router/events-YYYY-MM-DD.json`.

## Important: keep docs in sync

When changing the router integration code (`RouterService.swift`), always update `docs/router-api.md` to match. That file documents the actual API response formats, parsing gotchas, and endpoint behavior — it's the reference for anyone debugging the integration.

## Testing notes

The router API response format is documented in `docs/router-api.md`. A debug response is saved to `router/debug-response.txt` on each poll for inspection.
