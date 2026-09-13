import SwiftUI
import Charts

struct LatencyChartView: View {
    let selectedDate: Date
    @Environment(PingStore.self) private var pingStore

    private var records: [PingRecord] {
        pingStore.records(for: selectedDate)
    }

    private var buckets: [PingChartBucket] {
        PingChartBucket.aggregate(records)
    }

    private var chartMax: Double {
        let maxRecorded = buckets.compactMap(\.maxLatency).max() ?? 100
        return max(maxRecorded * 1.2, 100)
    }

    private var connections: [String] {
        Array(Set(buckets.map(\.connection))).sorted()
    }

    private var networkChanges: [Date] {
        networkChangeTimestamps(from: records)
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
                    ForEach(buckets) { bucket in
                        if let latency = bucket.avgLatency {
                            LineMark(
                                x: .value("Time", bucket.timestamp),
                                y: .value("Latency", latency),
                                series: .value("Segment", bucket.segment)
                            )
                            .foregroundStyle(by: .value("Connection", bucket.connection))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))

                            PointMark(
                                x: .value("Time", bucket.timestamp),
                                y: .value("Latency", latency)
                            )
                            .foregroundStyle(by: .value("Connection", bucket.connection))
                            .symbolSize(8)
                        }
                    }

                    ForEach(networkChanges, id: \.self) { change in
                        RuleMark(x: .value("Network change", change))
                            .foregroundStyle(.gray.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .chartForegroundStyleScale(
                    domain: connections,
                    range: connections.map { connectionColor(for: $0) }
                )
                .chartLegend(.hidden)
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
                                    .frame(width: 56, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: 180)

                Label("Packet loss", systemImage: "exclamationmark.circle")
                    .font(.headline)
                    .padding(.top, 8)
                Text("Failed pings per 5 minutes · Gaps mean no recorded pings")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(buckets) { bucket in
                        if bucket.lossPercentage > 0 {
                            BarMark(
                                xStart: .value("Start", bucket.timestamp),
                                xEnd: .value("End", bucket.timestamp.addingTimeInterval(300)),
                                y: .value("Packet loss", bucket.lossPercentage)
                            )
                            .foregroundStyle(.red)
                        } else {
                            PointMark(
                                x: .value("Time", bucket.timestamp.addingTimeInterval(150)),
                                y: .value("Packet loss", 0)
                            )
                            .foregroundStyle(.secondary)
                            .symbolSize(6)
                        }
                    }
                    ForEach(networkChanges, id: \.self) { change in
                        RuleMark(x: .value("Network change", change))
                            .foregroundStyle(.gray.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .chartXScale(domain: startOfDay(selectedDate)...endOfDay(selectedDate))
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let loss = value.as(Int.self) {
                                Text("\(loss)%")
                                    .frame(width: 56, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: 100)
            }
        }
    }

    private static let palette: [Color] = [.blue, .purple, .teal, .indigo]

    private func connectionColor(for name: String) -> Color {
        guard let index = connections.firstIndex(of: name) else { return .blue }
        return Self.palette[index % Self.palette.count]
    }
}
