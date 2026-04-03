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
                        let short = PingRecord(success: true, connection: conn).shortConnection
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
                    Text("\(snap.rssi) dBm")
                        .font(.system(.caption, design: .monospaced))
                    Text(snap.signalQuality)
                        .font(.caption)
                        .foregroundStyle(signalColor)
                }
            }

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
