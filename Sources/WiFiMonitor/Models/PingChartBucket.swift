import Foundation

struct PingChartBucket: Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let avgLatency: Double?
    let maxLatency: Double?
    let connection: String
    let lossPercentage: Double
    let segment: Int

    static func aggregate(_ records: [PingRecord], calendar: Calendar = .current) -> [Self] {
        let known = records.compactMap(\.connection)
        let counts = Dictionary(grouping: known, by: { $0 }).mapValues(\.count)
        let fallback = shortConnectionName(counts.max(by: { $0.value < $1.value })?.key)
        let grouped = Dictionary(grouping: records) { record in
            let minute = calendar.component(.minute, from: record.timestamp)
            let hour = calendar.dateInterval(of: .hour, for: record.timestamp)!.start
            return hour.addingTimeInterval(Double(minute / 5) * 300)
        }
        var segment = 0
        var previousTimestamp: Date?
        var previousConnection: String?
        return grouped.keys.sorted().map { timestamp in
            let samples = grouped[timestamp]!
            let latencies = samples.filter(\.success).compactMap(\.latencyMs)
            let failures = samples.filter { !$0.success }.count
            let connections = Dictionary(grouping: samples, by: \.shortConnection).mapValues(\.count)
            var connection = connections.max(by: { $0.value < $1.value })?.key ?? fallback
            if connection == "Unknown" { connection = fallback }

            // Separate line series so Charts cannot connect across outages,
            // missing observations, or connection changes.
            if latencies.isEmpty || previousConnection != connection
                || previousTimestamp.map({ timestamp.timeIntervalSince($0) > 300 }) == true {
                segment += 1
            }
            let bucket = Self(
                timestamp: timestamp,
                avgLatency: latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count),
                maxLatency: latencies.max(),
                connection: connection,
                lossPercentage: Double(failures) / Double(samples.count) * 100,
                segment: segment
            )
            if latencies.isEmpty { segment += 1 }
            previousTimestamp = timestamp
            previousConnection = connection
            return bucket
        }
    }
}
