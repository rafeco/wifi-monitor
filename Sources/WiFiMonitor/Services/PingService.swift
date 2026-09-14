import CoreWLAN
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
    private var connectionLookupFailures: Int = 0
    private var cachedExternalIP: String?
    private var lastIPCheck: Date = .distantPast
    private var ipProbeWorking: Bool = false
    private var networkChangeObserver: NSObjectProtocol?

    func start(store: PingStore) {
        guard !isRunning else { return }
        self.store = store
        isRunning = true
        restoreCachedConnection()

        networkChangeObserver = NotificationCenter.default.addObserver(
            forName: .wifiNetworkChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleNetworkChange()
        }

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
        if let networkChangeObserver {
            NotificationCenter.default.removeObserver(networkChangeObserver)
        }
        networkChangeObserver = nil
    }

    /// The WiFi network changed, so the ISP almost certainly did too. Drop the
    /// cached org and re-detect on the spot rather than showing a stale
    /// provider for up to two minutes.
    private func handleNetworkChange() {
        cachedConnection = nil
        lastConnectionCheck = .distantPast
        connectionLookupFailures = 0
        cachedExternalIP = nil
        lastIPCheck = .distantPast
        UserDefaults.standard.removeObject(forKey: Self.cachedConnectionKey)
        // Clear the displayed provider too, so we don't show the old network's
        // ISP until the fresh lookup returns (or if it can't be reached).
        lastConnection = nil
        performPing()
    }

    private func performPing() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.executePing(host: "1.1.1.1")
            let connection = self?.fetchConnectionIfNeeded(pingSucceeded: result.success)
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

    /// An ISP lookup is only worth making when the thing it describes can have
    /// changed — and the external IP is the tell. Cloudflare's trace endpoint
    /// reports it in 192 bytes, is unmetered, and lives on the host we already
    /// ping, so we probe that often and spend an ipinfo request only when the
    /// IP actually moves.
    private static let ipCheckInterval: TimeInterval = 120

    /// Fallback cadence when the cheap IP probe is unavailable — the old
    /// timer-driven behavior, so losing Cloudflare degrades rather than blinds.
    private static let connectionPollInterval: TimeInterval = 900

    /// Safety net: re-confirm the ISP occasionally even on a stable IP, in case
    /// a provider change somehow didn't move it.
    private static let connectionRefreshCeiling: TimeInterval = 21600

    /// Returns the current ISP. Spends an ipinfo request only when we have no
    /// answer yet, when the external IP has changed under us, or when the cached
    /// answer is very old. Skips everything when the ping just failed, and backs
    /// off exponentially after a failed lookup, since the likeliest cause of one
    /// is that we're already rate-limited.
    private func fetchConnectionIfNeeded(pingSucceeded: Bool) -> String? {
        guard pingSucceeded else { return cachedConnection }
        let now = Date()

        var ipChanged = false
        if now.timeIntervalSince(lastIPCheck) >= Self.ipCheckInterval {
            lastIPCheck = now
            if let ip = Self.fetchExternalIP() {
                ipProbeWorking = true
                // A first-ever reading isn't a change, just a baseline.
                ipChanged = cachedExternalIP != nil && ip != cachedExternalIP
                cachedExternalIP = ip
                UserDefaults.standard.set(ip, forKey: Self.cachedExternalIPKey)
            } else {
                ipProbeWorking = false
            }
        }

        // Never retry a failed lookup sooner than the backoff allows.
        let sinceLastLookup = now.timeIntervalSince(lastConnectionCheck)
        if connectionLookupFailures > 0 {
            let backoff = min(Self.connectionPollInterval * pow(2.0, Double(connectionLookupFailures)), 7200)
            guard sinceLastLookup >= backoff else { return cachedConnection }
        }

        let staleAfter = ipProbeWorking ? Self.connectionRefreshCeiling : Self.connectionPollInterval
        let needsLookup = cachedConnection == nil || ipChanged || sinceLastLookup >= staleAfter
        guard needsLookup else { return cachedConnection }

        // Floor between lookups, so a flapping address (a dual-stack host whose
        // trace answers v4 and v6 alternately, say) can't spend a request per
        // probe. Worst case stays at the probe cadence; the normal case is zero.
        guard cachedConnection == nil || sinceLastLookup >= Self.ipCheckInterval else {
            return cachedConnection
        }

        lastConnectionCheck = now
        if let connection = Self.fetchConnection() {
            cachedConnection = connection
            connectionLookupFailures = 0
            persistCachedConnection(connection, at: now)
            return connection
        }
        connectionLookupFailures += 1
        return cachedConnection
    }

    /// The external IP as seen from the internet, via Cloudflare's trace
    /// endpoint (a `key=value` per line; we want `ip=`).
    static func fetchExternalIP() -> String? {
        guard let output = runCurl(url: "https://1.1.1.1/cdn-cgi/trace") else { return nil }
        for line in output.split(separator: "\n") where line.hasPrefix("ip=") {
            let ip = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return ip.isEmpty ? nil : ip
        }
        return nil
    }

    // MARK: - Cross-launch cache

    private static let cachedConnectionKey = "cachedConnection"
    private static let cachedConnectionDateKey = "cachedConnectionDate"
    private static let cachedConnectionSSIDKey = "cachedConnectionSSID"
    private static let cachedExternalIPKey = "cachedExternalIP"

    private var currentSSID: String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    private func persistCachedConnection(_ connection: String, at date: Date) {
        let defaults = UserDefaults.standard
        defaults.set(connection, forKey: Self.cachedConnectionKey)
        defaults.set(date, forKey: Self.cachedConnectionDateKey)
        defaults.set(currentSSID, forKey: Self.cachedConnectionSSIDKey)
    }

    /// Restore the last known ISP so a relaunch doesn't cost a lookup. Only
    /// trusted while we're still on the network it was measured on and it's
    /// younger than the poll interval; otherwise the first ping re-detects.
    private func restoreCachedConnection() {
        let defaults = UserDefaults.standard
        guard let connection = defaults.string(forKey: Self.cachedConnectionKey),
              isPlausibleConnectionName(connection),
              let date = defaults.object(forKey: Self.cachedConnectionDateKey) as? Date,
              Date().timeIntervalSince(date) < Self.connectionPollInterval,
              defaults.string(forKey: Self.cachedConnectionSSIDKey) == currentSSID
        else { return }
        cachedConnection = connection
        lastConnection = connection
        lastConnectionCheck = date
        // Restore the IP this org was measured at, so an address that moved
        // while the app was closed still registers as a change.
        cachedExternalIP = defaults.string(forKey: Self.cachedExternalIPKey)
    }

    static func fetchConnection() -> String? {
        guard let output = runCurl(url: "https://ipinfo.io/org"),
              isPlausibleConnectionName(output) else { return nil }
        return output
    }

    /// Fetch a small text response, or nil on any failure. `-f` makes curl exit
    /// non-zero on an HTTP error rather than handing back the response body —
    /// ipinfo.io answers a rate-limited request with a JSON error blob.
    private static func runCurl(url: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-sf", "--max-time", "3", url]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty else { return nil }
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
