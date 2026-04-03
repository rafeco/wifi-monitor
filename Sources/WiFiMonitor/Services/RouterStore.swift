import Foundation

@Observable
final class RouterStore {
    private let storageDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("WiFiMonitor/router", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Snapshots

    func addSnapshot(_ snapshot: RouterSnapshot) {
        let url = snapshotFileURL(for: snapshot.timestamp)
        var existing = loadSnapshots(for: snapshot.timestamp)
        existing.append(snapshot)
        if let data = try? encoder.encode(existing) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func snapshots(for date: Date) -> [RouterSnapshot] {
        loadSnapshots(for: date)
    }

    private func loadSnapshots(for date: Date) -> [RouterSnapshot] {
        let url = snapshotFileURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([RouterSnapshot].self, from: data)) ?? []
    }

    private func snapshotFileURL(for date: Date) -> URL {
        let name = Self.dateString(from: date)
        return storageDir.appendingPathComponent("snapshots-\(name).json")
    }

    // MARK: - Provider Events

    func addProviderEvent(_ event: ProviderEvent) {
        let url = eventsFileURL(for: event.timestamp)
        var existing = loadProviderEvents(for: event.timestamp)
        existing.append(event)
        if let data = try? encoder.encode(existing) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func providerEvents(for date: Date) -> [ProviderEvent] {
        loadProviderEvents(for: date)
    }

    private func loadProviderEvents(for date: Date) -> [ProviderEvent] {
        let url = eventsFileURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([ProviderEvent].self, from: data)) ?? []
    }

    private func eventsFileURL(for date: Date) -> URL {
        let name = Self.dateString(from: date)
        return storageDir.appendingPathComponent("events-\(name).json")
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dateString(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
