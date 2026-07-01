import SwiftUI

struct StatusBarView: View {
    let selectedDate: Date
    @Environment(PingService.self) private var pingService
    @Environment(PingStore.self) private var pingStore
    @Environment(WiFiService.self) private var wifiService

    private var records: [PingRecord] {
        pingStore.records(for: selectedDate)
    }

    private var uptimePercentage: Double {
        guard !records.isEmpty else { return 100 }
        let successful = records.filter(\.success).count
        return Double(successful) / Double(records.count) * 100
    }

    private var averageLatency: Double? {
        let latencies = records.compactMap(\.latencyMs)
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    private var currentStatusColor: Color {
        guard pingService.lastSuccess else { return .red }
        guard let latency = pingService.lastLatency else { return .green }
        if latency <= 50 { return .green }
        if latency <= 200 { return .yellow }
        return .orange
    }

    private var signalColor: Color {
        guard let snap = wifiService.lastSnapshot else { return .secondary }
        if snap.rssi > -60 { return .green }
        if snap.rssi > -75 { return .yellow }
        return .red
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(currentStatusColor)
                    .frame(width: 12, height: 12)

                if pingService.lastSuccess, let latency = pingService.lastLatency {
                    Text(String(format: "%.0f ms", latency))
                        .font(.system(.body, design: .monospaced))
                    if let conn = pingService.lastConnection {
                        let short = shortConnectionName(conn)
                        Text("via \(short)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !pingService.isRunning {
                    Text("Not monitoring")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Timeout")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }

            if let snap = wifiService.lastSnapshot {
                Divider().frame(height: 16)
                HStack(spacing: 4) {
                    Image(systemName: "wifi")
                        .foregroundStyle(signalColor)
                    if let ssid = wifiService.currentSSID {
                        Text(ssid)
                            .font(.caption.weight(.medium))
                    }
                    Text("\(snap.rssi) dBm")
                        .font(.system(.caption, design: .monospaced))
                    Text(snap.signalQuality)
                        .font(.caption)
                        .foregroundStyle(signalColor)
                }
            }

            Divider().frame(height: 16)
            FeelsLikeView()

            Spacer()

            HStack(spacing: 16) {
                if let avg = averageLatency {
                    Label(String(format: "Avg: %.0f ms", avg), systemImage: "timer")
                }

                Label(
                    String(format: "Uptime: %.1f%%", uptimePercentage),
                    systemImage: uptimePercentage >= 99 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(uptimePercentage >= 99 ? .green : (uptimePercentage >= 95 ? .orange : .red))

                Label("\(records.count) pings", systemImage: "network")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Live "feels like" indicator: a single rating that blends recent latency,
/// jitter, and packet loss, with cause attribution distinguishing upstream
/// (ISP) problems from local WiFi ones. Always reflects "right now" (today's
/// most recent pings), regardless of the day being viewed elsewhere.
struct FeelsLikeView: View {
    @Environment(PingStore.self) private var pingStore
    @Environment(WiFiService.self) private var wifiService
    @Environment(RouterService.self) private var routerService
    @AppStorage("routerEnabled") private var routerEnabled = true

    private var score: FeelsLikeScore {
        let recent = Array(pingStore.records(for: Date()).suffix(10))

        let wanConnected: Bool?
        var throughput: Double?
        var peakThroughput: Double?
        if routerEnabled, let wan = routerService.wanStatus {
            // Only treat as down on an explicit disconnect; the status string
            // format varies, so avoid false alarms from unexpected values.
            wanConnected = !wan.status.lowercased().contains("disconnect")

            if let latest = routerService.history.last {
                throughput = latest.rxBytesPerSec + latest.txBytesPerSec
            }
            // Scope the saturation baseline to the current network session so a
            // fast prior network's peak doesn't suppress bufferbloat detection
            // after switching to a slower one.
            peakThroughput = routerService.history
                .filter { $0.timestamp >= wifiService.lastNetworkChange }
                .map { $0.rxBytesPerSec + $0.txBytesPerSec }
                .max()
        } else {
            wanConnected = nil
        }

        return FeelsLikeScore.compute(
            recentPings: recent,
            wifi: wifiService.lastSnapshot,
            wanConnected: wanConnected,
            throughputBytesPerSec: throughput,
            peakThroughputBytesPerSec: peakThroughput
        )
    }

    var body: some View {
        let s = score
        HStack(spacing: 6) {
            Image(systemName: s.rating.symbol)
                .foregroundStyle(s.rating.color)
            VStack(alignment: .leading, spacing: 1) {
                Text("Feels \(s.rating.rawValue)")
                    .font(.callout.weight(.medium))
                if let cause = s.cause.description {
                    Text(cause)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .help("Network feels-like score: \(s.score)/100")
    }
}
