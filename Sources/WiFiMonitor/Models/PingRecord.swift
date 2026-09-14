import Foundation
import SwiftUI

/// ipinfo.io answers a rate-limited (HTTP 429) lookup with a JSON error body
/// rather than an org string. Anything JSON-shaped, multi-line, or implausibly
/// long is not an ISP name, so treat it as unknown instead of charting it as a
/// distinct connection.
func isPlausibleConnectionName(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 100 else { return false }
    if trimmed.contains(where: { $0.isNewline }) { return false }
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") || trimmed.hasPrefix("<") { return false }
    return true
}

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

    /// Older files can hold a garbage connection string captured before the
    /// ISP lookup validated its response (an ipinfo rate-limit body, say).
    /// Drop those on read so the charts don't show them as a network.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latencyMs = try container.decodeIfPresent(Double.self, forKey: .latencyMs)
        success = try container.decode(Bool.self, forKey: .success)
        host = try container.decode(String.self, forKey: .host)
        let rawConnection = try container.decodeIfPresent(String.self, forKey: .connection)
        connection = rawConnection.flatMap { isPlausibleConnectionName($0) ? $0 : nil }
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
