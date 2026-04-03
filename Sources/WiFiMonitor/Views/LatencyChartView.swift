import SwiftUI
import Charts

struct ChartBucket: Identifiable {
    let id = UUID()
    let timestamp: Date
    let avgLatency: Double
    let maxLatency: Double
    let connection: String
    let hadFailure: Bool
}

struct LatencyChartView: View {
    let selectedDate: Date
    @Environment(PingStore.self) private var pingStore

    private var records: [PingRecord] {
        pingStore.records(for: selectedDate)
    }

    /// Most common known connection name for the day, used as fallback for nil records
    private var primaryConnection: String {
        let known = records.compactMap(\.connection)
        guard !known.isEmpty else { return "Unknown" }
        let counts = Dictionary(grouping: known, by: { $0 }).mapValues(\.count)
        return shortConnectionName(counts.max(by: { $0.value < $1.value })!.key)
    }

    /// Aggregate records into 5-minute buckets
    private var buckets: [ChartBucket] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { record -> Date in
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.timestamp)
            let roundedMinute = (comps.minute! / 5) * 5
            return calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: comps.hour, minute: roundedMinute
            ))!
        }
        return grouped.map { (timestamp, records) in
            let latencies = records.compactMap(\.latencyMs)
            let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
            let max = latencies.max() ?? 0
            let hadFailure = records.contains { !$0.success }
            // Use most common connection in bucket, falling back to primary
            let connCounts = Dictionary(grouping: records, by: { $0.shortConnection }).mapValues(\.count)
            var conn = connCounts.max(by: { $0.value < $1.value })?.key ?? primaryConnection
            if conn == "Unknown" { conn = primaryConnection }
            return ChartBucket(timestamp: timestamp, avgLatency: avg, maxLatency: max, connection: conn, hadFailure: hadFailure)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    private var chartMax: Double {
        let maxRecorded = buckets.map(\.maxLatency).max() ?? 100
        return max(maxRecorded * 1.2, 100)
    }

    private var connections: [String] {
        Array(Set(buckets.map(\.connection))).sorted()
    }

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView(
                "No Data",
                systemImage: "wifi.slash",
                description: Text("No ping data recorded for this day.\nKeep the app running to collect data.")
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if connections.count > 1 {
                    HStack(spacing: 12) {
                        Text("Connections:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(connections, id: \.self) { name in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(connectionColor(for: name))
                                    .frame(width: 8, height: 8)
                                Text(name)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Chart(buckets) { bucket in
                    LineMark(
                        x: .value("Time", bucket.timestamp),
                        y: .value("Latency", bucket.avgLatency)
                    )
                    .foregroundStyle(by: .value("Connection", bucket.connection))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartForegroundStyleScale(
                    domain: connections,
                    range: connections.map { connectionColor(for: $0) }
                )
                .chartLegend(connections.count > 1 ? .visible : .hidden)
                .chartXScale(domain: startOfDay(selectedDate)...endOfDay(selectedDate))
                .chartYScale(domain: 0...chartMax)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v)) ms")
                            }
                        }
                    }
                }
            }
        }
    }

    private static let palette: [Color] = [.blue, .purple, .teal, .indigo]

    private func connectionColor(for name: String) -> Color {
        guard let index = connections.firstIndex(of: name) else { return .blue }
        return Self.palette[index % Self.palette.count]
    }
}
