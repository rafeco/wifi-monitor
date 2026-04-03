import SwiftUI

struct StatusBarView: View {
    let selectedDate: Date
    @Environment(PingService.self) private var pingService
    @Environment(PingStore.self) private var pingStore

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

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(currentStatusColor)
                    .frame(width: 12, height: 12)

                if pingService.lastSuccess, let latency = pingService.lastLatency {
                    Text(String(format: "Current: %.0f ms", latency))
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
                    Text("Current: Timeout")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
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
