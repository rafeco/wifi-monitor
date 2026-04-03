import Foundation

@Observable
final class PingStore {
    private(set) var records: [PingRecord] = []
    private let storageDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("WiFiMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadToday()
    }

    func add(_ record: PingRecord) {
        records.append(record)
        save(record)
    }

    func records(for date: Date) -> [PingRecord] {
        let loaded = loadRecords(for: date)
        // If it's today, merge with in-memory records
        if Calendar.current.isDateInToday(date) {
            let diskIDs = Set(loaded.map(\.id))
            let newOnly = records.filter { !diskIDs.contains($0.id) }
            return (loaded + newOnly).sorted { $0.timestamp < $1.timestamp }
        }
        return loaded
    }

    // MARK: - File I/O

    private func fileURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = formatter.string(from: date)
        return storageDir.appendingPathComponent("\(name).json")
    }

    private func loadToday() {
        records = loadRecords(for: Date())
    }

    private func loadRecords(for date: Date) -> [PingRecord] {
        let url = fileURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PingRecord].self, from: data)) ?? []
    }

    private func save(_ record: PingRecord) {
        let url = fileURL(for: record.timestamp)
        var existing = loadRecords(for: record.timestamp)
        existing.append(record)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(existing) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
