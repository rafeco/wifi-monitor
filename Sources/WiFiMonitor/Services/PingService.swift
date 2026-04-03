import Foundation

@Observable
final class PingService {
    var lastLatency: Double?
    var lastSuccess: Bool = true
    var lastConnection: String?
    var isRunning: Bool = false

    private var timer: Timer?
    private weak var store: PingStore?
    private var cachedConnection: String?
    private var lastConnectionCheck: Date = .distantPast

    func start(store: PingStore) {
        guard !isRunning else { return }
        self.store = store
        isRunning = true

        performPing()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.performPing()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func performPing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.executePing(host: "1.1.1.1")
            let connection = self?.fetchConnectionIfNeeded()
            DispatchQueue.main.async {
                self?.lastLatency = result.latency
                self?.lastSuccess = result.success
                if let connection { self?.lastConnection = connection }
                self?.saveRecord(result)
            }
        }
    }

    private func saveRecord(_ result: PingResult) {
        let record = PingRecord(latencyMs: result.latency, success: result.success, connection: lastConnection)
        store?.add(record)
    }

    /// Check ISP every 2 minutes (not every ping) to avoid hammering the API
    private func fetchConnectionIfNeeded() -> String? {
        let now = Date()
        if let cached = cachedConnection, now.timeIntervalSince(lastConnectionCheck) < 120 {
            return cached
        }
        let connection = Self.fetchConnection()
        if let connection {
            cachedConnection = connection
            lastConnectionCheck = now
        }
        return connection ?? cachedConnection
    }

    static func fetchConnection() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "--max-time", "3", "https://ipinfo.io/org"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }
        return output
    }

    static func executePing(host: String) -> PingResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "3000", host]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return PingResult(success: false, latency: nil)
        }

        guard process.terminationStatus == 0 else {
            return PingResult(success: false, latency: nil)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return PingResult(success: false, latency: nil)
        }

        if let range = output.range(of: #"time=(\d+\.?\d*)"#, options: .regularExpression) {
            let match = output[range]
            let numberStr = match.replacingOccurrences(of: "time=", with: "")
            if let latency = Double(numberStr) {
                return PingResult(success: true, latency: latency)
            }
        }

        return PingResult(success: false, latency: nil)
    }
}

struct PingResult {
    let success: Bool
    let latency: Double?
}
