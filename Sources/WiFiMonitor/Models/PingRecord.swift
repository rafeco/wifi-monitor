import Foundation
import SwiftUI

/// Strip the "ASXXXXX " prefix from org strings like "AS29852 Honest Networks, LLC"
func shortConnectionName(_ connection: String?) -> String {
    guard let connection else { return "Unknown" }
    if let spaceIndex = connection.firstIndex(of: " "),
       connection.prefix(2) == "AS" {
        return String(connection[connection.index(after: spaceIndex)...])
    }
    return connection
}

/// Timestamps where the detected connection (ISP) changes across the day —
/// used to draw network-change markers on the charts. Records without a known
/// connection are skipped so a temporary lookup gap isn't mistaken for a switch.
func networkChangeTimestamps(from records: [PingRecord]) -> [Date] {
    let sorted = records.sorted { $0.timestamp < $1.timestamp }
    var changes: [Date] = []
    var previous: String?
    for record in sorted {
        guard let connection = record.connection else { continue }
        let name = shortConnectionName(connection)
        if let previous, name != previous {
            changes.append(record.timestamp)
        }
        previous = name
    }
    return changes
}

struct PingRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let latencyMs: Double?
    let success: Bool
    let host: String
    let connection: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), latencyMs: Double? = nil, success: Bool, host: String = "1.1.1.1", connection: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.latencyMs = latencyMs
        self.success = success
        self.host = host
        self.connection = connection
    }

    var shortConnection: String {
        shortConnectionName(connection)
    }

    var statusColor: Color {
        guard success, let latency = latencyMs else { return .red }
        if latency <= 50 { return .green }
        if latency <= 200 { return .yellow }
        return .orange
    }

    var statusLabel: String {
        guard success, let latency = latencyMs else { return "Timeout" }
        return String(format: "%.0f ms", latency)
    }
}
