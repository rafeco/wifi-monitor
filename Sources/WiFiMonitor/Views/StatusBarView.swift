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
        HStack(alignment: .center, spacing: 20) {
            // Prominent "feels like" weather headline.
            FeelsLikeView()

            Spacer()

            // Everything else, arranged cleanly on the right.
            VStack(alignment: .trailing, spacing: 4) {
                pingRow
                if wifiService.lastSnapshot != nil { wifiRow }
                statsRow
            }
        }
    }

    private var pingRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(currentStatusColor)
                .frame(width: 8, height: 8)

            if pingService.lastSuccess, let latency = pingService.lastLatency {
                Text(String(format: "%.0f ms", latency))
                    .font(.system(.callout, design: .monospaced))
                if let conn = pingService.lastConnection {
                    Text("via \(shortConnectionName(conn))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !pingService.isRunning {
                Text("Not monitoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Timeout")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var wifiRow: some View {
        if let snap = wifiService.lastSnapshot {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .foregroundStyle(signalColor)
                if let ssid = wifiService.currentSSID {
                    Text(ssid)
                        .font(.caption.weight(.medium))
                }
                if snap.band != "Unknown" {
                    Text(snap.band)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(snap.rssi) dBm")
                    .font(.system(.caption, design: .monospaced))
                Text(snap.signalQuality)
                    .font(.caption)
                    .foregroundStyle(signalColor)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            Label(
                String(format: "Uptime %.1f%%", uptimePercentage),
                systemImage: uptimePercentage >= 99 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(uptimePercentage >= 99 ? .green : (uptimePercentage >= 95 ? .orange : .red))

            Label("\(records.count) pings", systemImage: "network")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
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
        HStack(spacing: 12) {
            Image(systemName: s.rating.symbol)
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(s.rating.color)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Feels \(s.rating.rawValue)")
                    .font(.title2.weight(.semibold))
                if let cause = s.cause.description {
                    Text(cause)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .help("Network feels-like score: \(s.score)/100")
    }
}
