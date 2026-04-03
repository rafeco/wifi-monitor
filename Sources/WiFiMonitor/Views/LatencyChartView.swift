import SwiftUI
import Charts

struct LatencyChartView: View {
    let selectedDate: Date
    @Environment(PingStore.self) private var pingStore

    private var records: [PingRecord] {
        pingStore.records(for: selectedDate)
    }

    private var maxLatency: Double {
        let maxRecorded = records.compactMap(\.latencyMs).max() ?? 100
        return max(maxRecorded * 1.2, 100)
    }

    private var successRecords: [PingRecord] {
        records.filter { $0.success && $0.latencyMs != nil }
    }

    private var failureRecords: [PingRecord] {
        records.filter { !$0.success }
    }

    private var connections: [String] {
        Array(Set(records.compactMap(\.connection).map { PingRecord(success: true, connection: $0).shortConnection })).sorted()
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

                Chart {
                    RuleMark(y: .value("Good", 50))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(.green.opacity(0.4))

                    RuleMark(y: .value("Slow", 200))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        .foregroundStyle(.orange.opacity(0.4))

                    ForEach(successRecords) { record in
                        BarMark(
                            x: .value("Time", record.timestamp),
                            y: .value("Latency", record.latencyMs ?? 0)
                        )
                        .foregroundStyle(connectionColor(for: record.shortConnection))
                    }

                    ForEach(failureRecords) { record in
                        PointMark(
                            x: .value("Time", record.timestamp),
                            y: .value("Latency", maxLatency)
                        )
                        .foregroundStyle(.red)
                        .symbolSize(40)
                        .symbol(.cross)
                    }
                }
            .chartXScale(domain: startOfDay(selectedDate)...endOfDay(selectedDate))
            .chartYScale(domain: 0...maxLatency)
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
