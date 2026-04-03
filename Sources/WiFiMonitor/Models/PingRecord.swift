import Foundation
import SwiftUI

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
        guard let connection else { return "Unknown" }
        // Strip the "ASXXXXX " prefix from org strings like "AS29852 Honest Networks, LLC"
        if let spaceIndex = connection.firstIndex(of: " "),
           connection[connection.startIndex...].prefix(2) == "AS" {
            return String(connection[connection.index(after: spaceIndex)...])
        }
        return connection
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
