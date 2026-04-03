import SwiftUI
import Charts

struct WiFiSignalBucket: Identifiable {
    let id = UUID()
    let timestamp: Date
    let avgRssi: Double
    let avgSnr: Double
    let avgTxRate: Double
}

struct WiFiSignalChartView: View {
    let selectedDate: Date
    @Environment(WiFiStore.self) private var wifiStore

    private var snapshots: [WiFiSnapshot] {
        // Access updateCount to trigger re-render when new data arrives
        let _ = wifiStore.updateCount
        return wifiStore.snapshots(for: selectedDate).filter { $0.rssi != 0 }
    }

    private var buckets: [WiFiSignalBucket] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: snapshots) { snap -> Date in
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: snap.timestamp)
            let roundedMinute = (comps.minute! / 5) * 5
            return calendar.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day,
                hour: comps.hour, minute: roundedMinute
            ))!
        }
        return grouped.map { (timestamp, snaps) in
            let avgRssi = snaps.map { Double($0.rssi) }.reduce(0, +) / Double(snaps.count)
            let avgSnr = snaps.map { Double($0.snr) }.reduce(0, +) / Double(snaps.count)
            let avgTxRate = snaps.map(\.txRate).reduce(0, +) / Double(snaps.count)
            return WiFiSignalBucket(timestamp: timestamp, avgRssi: avgRssi, avgSnr: avgSnr, avgTxRate: avgTxRate)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        if snapshots.isEmpty {
            ContentUnavailableView(
                "No WiFi Data",
                systemImage: "wifi.slash",
                description: Text("No WiFi signal data recorded for this day.")
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("WiFi Signal", systemImage: "wifi")
                        .font(.headline)
                    Spacer()
                    if let last = snapshots.last {
                        Text("\(last.channel) (\(last.band))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("TX: \(Int(last.txRate)) Mbps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Chart(buckets) { bucket in
                    LineMark(
                        x: .value("Time", bucket.timestamp),
                        y: .value("RSSI", bucket.avgRssi)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Time", bucket.timestamp),
                        y: .value("RSSI", bucket.avgRssi)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(15)
                }
                .chartBackground { proxy in
                    GeometryReader { geo in
                        let plotArea = proxy.plotSize
                        // Green zone: -30 to -60
                        Rectangle()
                            .fill(.green.opacity(0.06))
                            .frame(height: plotArea.height * (30.0 / 65.0))
                        // Yellow zone: -60 to -75
                        Rectangle()
                            .fill(.yellow.opacity(0.06))
                            .frame(height: plotArea.height * (15.0 / 65.0))
                            .offset(y: plotArea.height * (30.0 / 65.0))
                        // Red zone: -75 to -95
                        Rectangle()
                            .fill(.red.opacity(0.06))
                            .frame(height: plotArea.height * (20.0 / 65.0))
                            .offset(y: plotArea.height * (45.0 / 65.0))
                    }
                }
                .chartXScale(domain: startOfDay(selectedDate)...endOfDay(selectedDate))
                .chartYScale(domain: -95...(-30))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [-90, -75, -60, -45, -30]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v) dBm")
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}
