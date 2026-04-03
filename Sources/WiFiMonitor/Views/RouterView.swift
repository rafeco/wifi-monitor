import SwiftUI
import Charts

struct RouterView: View {
    @Environment(RouterService.self) private var router
    @Environment(PingService.self) private var pingService

    var body: some View {
        if !router.isConnected && !router.isPolling {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "Router Not Connected",
                    systemImage: "wifi.router",
                    description: Text(router.lastError ?? "Open Settings (⌘,) to configure your router connection.")
                )
                Button("Connect Now") {
                    router.start()
                }
                .buttonStyle(.bordered)
            }
        } else if !router.isConnected {
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting to router...")
                    .foregroundStyle(.secondary)
                if let error = router.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    providerCard
                    wanCard
                    HStack(spacing: 16) {
                        cpuCard
                        memoryCard
                    }
                    if router.history.count > 1 {
                        bandwidthChart
                        performanceChart
                    }
                    if !router.providerEvents.isEmpty {
                        eventLog
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Current Provider

    private var providerCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let conn = pingService.lastConnection {
                        let short = PingRecord(success: true, connection: conn).shortConnection
                        Text(short)
                            .font(.title3.bold())
                    } else {
                        Text("Detecting...")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let wan = router.wanStatus {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("WAN IP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(wan.ip.isEmpty ? "—" : wan.ip)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
    }

    // MARK: - WAN Status Card

    private var wanCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("WAN Connection", systemImage: "network")
                    .font(.headline)

                if let wan = router.wanStatus {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ], spacing: 8) {
                        StatRow(label: "Status", value: wan.status == "1" ? "Connected" : wan.status,
                                color: wan.status == "1" ? .green : .red)
                        StatRow(label: "Type", value: wan.wanType.isEmpty ? "—" : wan.wanType)
                        StatRow(label: "Gateway", value: wan.gateway.isEmpty ? "—" : wan.gateway)
                        StatRow(label: "DNS", value: wan.dns.isEmpty ? "—" : wan.dns)
                    }
                } else {
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - CPU Card

    private var cpuCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("CPU", systemImage: "cpu")
                    .font(.headline)

                if let cpu = router.cpuUsage {
                    VStack(alignment: .leading, spacing: 6) {
                        UsageBar(label: "Average", percent: cpu.average)
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { i in
                                let value = [cpu.core1, cpu.core2, cpu.core3, cpu.core4][i]
                                VStack(spacing: 2) {
                                    Text("\(value)%")
                                        .font(.system(.caption, design: .monospaced))
                                    Text("Core \(i + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Memory", systemImage: "memorychip")
                    .font(.headline)

                if let mem = router.memoryUsage {
                    VStack(alignment: .leading, spacing: 6) {
                        UsageBar(label: "Used", percent: Int(mem.usedPercent))

                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text("\(mem.usedMB) MB")
                                    .font(.system(.caption, design: .monospaced))
                                Text("Used")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading) {
                                Text("\(mem.freeMB) MB")
                                    .font(.system(.caption, design: .monospaced))
                                Text("Free")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading) {
                                Text("\(mem.totalMB) MB")
                                    .font(.system(.caption, design: .monospaced))
                                Text("Total")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bandwidth Chart

    private var bandwidthChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Bandwidth", systemImage: "arrow.up.arrow.down")
                    .font(.headline)

                Chart {
                    ForEach(router.history) { snap in
                        LineMark(
                            x: .value("Time", snap.timestamp),
                            y: .value("Speed", snap.rxBytesPerSec / 1024)
                        )
                        .foregroundStyle(by: .value("Direction", "Download"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        LineMark(
                            x: .value("Time", snap.timestamp),
                            y: .value("Speed", snap.txBytesPerSec / 1024)
                        )
                        .foregroundStyle(by: .value("Direction", "Upload"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartForegroundStyleScale([
                    "Download": Color.blue,
                    "Upload": Color.green
                ])
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatBandwidth(v))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Performance Chart (CPU + Memory over time)

    private var performanceChart: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Performance", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.headline)

                Chart {
                    ForEach(router.history) { snap in
                        LineMark(
                            x: .value("Time", snap.timestamp),
                            y: .value("Percent", snap.cpuPercent)
                        )
                        .foregroundStyle(by: .value("Metric", "CPU"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        LineMark(
                            x: .value("Time", snap.timestamp),
                            y: .value("Percent", snap.memoryPercent)
                        )
                        .foregroundStyle(by: .value("Metric", "Memory"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartForegroundStyleScale([
                    "CPU": Color.orange,
                    "Memory": Color.purple
                ])
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Provider Switch Event Log

    private var eventLog: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Provider Switches", systemImage: "arrow.triangle.swap")
                    .font(.headline)

                ForEach(router.providerEvents.reversed()) { event in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.orange)
                        Text(event.timestamp, format: .dateTime.hour().minute().second())
                            .font(.system(.caption, design: .monospaced))
                        Text(event.from)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(event.to)
                            .bold()
                    }
                    .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func formatBandwidth(_ kbPerSec: Double) -> String {
        if kbPerSec >= 1024 {
            return String(format: "%.1f MB/s", kbPerSec / 1024)
        }
        return String(format: "%.0f KB/s", kbPerSec)
    }
}

// MARK: - Helper Views

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

struct UsageBar: View {
    let label: String
    let percent: Int

    private var barColor: Color {
        if percent < 50 { return .green }
        if percent < 80 { return .yellow }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(.system(.caption, design: .monospaced))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}
