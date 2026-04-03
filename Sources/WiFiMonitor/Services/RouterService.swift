import Foundation

struct WanStatus {
    var ip: String
    var gateway: String
    var dns: String
    var status: String
    var wanType: String
}

struct CpuUsage {
    var core1: Int
    var core2: Int
    var core3: Int
    var core4: Int

    var average: Int { (core1 + core2 + core3 + core4) / 4 }
}

struct MemoryUsage {
    var totalKB: Int
    var usedKB: Int

    var usedPercent: Double {
        guard totalKB > 0 else { return 0 }
        return Double(usedKB) / Double(totalKB) * 100
    }

    var totalMB: Int { totalKB / 1024 }
    var usedMB: Int { usedKB / 1024 }
    var freeMB: Int { (totalKB - usedKB) / 1024 }
}

struct RouterSnapshot: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let cpuPercent: Int
    let memoryPercent: Int
    let rxBytesPerSec: Double
    let txBytesPerSec: Double

    init(id: UUID = UUID(), timestamp: Date = Date(), cpuPercent: Int, memoryPercent: Int, rxBytesPerSec: Double, txBytesPerSec: Double) {
        self.id = id
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
    }
}

struct ProviderEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let from: String
    let to: String

    init(id: UUID = UUID(), timestamp: Date = Date(), from: String, to: String) {
        self.id = id
        self.timestamp = timestamp
        self.from = from
        self.to = to
    }
}

@Observable
final class RouterService {
    var wanStatus: WanStatus?
    var cpuUsage: CpuUsage?
    var memoryUsage: MemoryUsage?
    var isConnected: Bool = false
    var lastError: String?
    var isPolling: Bool = false

    /// Time-series for charts
    var history: [RouterSnapshot] = []

    /// Provider switch event log
    var providerEvents: [ProviderEvent] = []
    private var lastSeenProvider: String?

    /// Traffic counter tracking for bandwidth calculation
    private var lastRxBytes: Int64?
    private var lastTxBytes: Int64?
    private var lastTrafficTime: Date?

    /// CPU counter tracking for delta-based percentage
    private var lastCpuTotal: [Int] = []
    private var lastCpuUsage: [Int] = []

    private var token: String?
    private var timer: Timer?
    private let session: URLSession
    private var store: RouterStore?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        // ASUS routers use self-signed certs on HTTPS; we use HTTP
        session = URLSession(configuration: config)
    }

    // MARK: - Public

    func start(store: RouterStore? = nil) {
        guard !isPolling else { return }
        if let store { self.store = store }
        let password = UserDefaults.standard.string(forKey: "routerPassword") ?? ""
        guard !password.isEmpty else {
            lastError = "No router password configured. Open Settings (⌘,) to set it up."
            return
        }
        // Load today's persisted history
        if let store = self.store {
            history = store.snapshots(for: Date())
            providerEvents = store.providerEvents(for: Date())
        }
        isPolling = true
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPolling = false
    }

    func testConnection(host: String, username: String, password: String) async -> String? {
        do {
            let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: "http://\(cleanHost)/login.cgi") else { return "Invalid URL for host: '\(host)'" }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("asusrouter-Android-DUTUtil-1.0.0.245", forHTTPHeaderField: "User-Agent")
            let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
            request.httpBody = "login_authorization=\(credentials)".data(using: .utf8)

            let (data, _) = try await session.data(for: request)
            let responseStr = String(data: data, encoding: .utf8) ?? "(no body)"
            if responseStr.contains("asus_token") {
                let t = try await authenticate(host: host, username: username, password: password)
                return t != nil ? nil : "Token parse failed. Response: \(responseStr.prefix(100))"
            }
            return "No token in response: \(responseStr.prefix(150))"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Private

    private var routerHost: String {
        UserDefaults.standard.string(forKey: "routerIP") ?? "192.168.50.1"
    }

    private var routerUsername: String {
        UserDefaults.standard.string(forKey: "routerUsername") ?? "admin"
    }

    private var routerPassword: String {
        UserDefaults.standard.string(forKey: "routerPassword") ?? ""
    }

    private func poll() {
        Task { @MainActor in
            do {
                // Authenticate if needed
                if token == nil {
                    token = try await authenticate(
                        host: routerHost, username: routerUsername, password: routerPassword
                    )
                }

                guard let token else {
                    lastError = "Authentication failed"
                    isConnected = false
                    return
                }

                // Fetch data
                let data = try await fetchData(host: routerHost, token: token)
                #if DEBUG
                let debugURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("WiFiMonitor/router/debug-response.txt")
                if let debugURL { try? data.write(to: debugURL, atomically: true, encoding: .utf8) }
                #endif
                parseResponse(data)
                isConnected = true
                lastError = nil
            } catch {
                // Token might be expired, clear it so we re-auth next time
                self.token = nil
                isConnected = false
                lastError = error.localizedDescription
            }
        }
    }

    private func authenticate(host: String, username: String, password: String) async throws -> String? {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "http://\(cleanHost)/login.cgi") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("asusrouter-Android-DUTUtil-1.0.0.245", forHTTPHeaderField: "User-Agent")

        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        request.httpBody = "login_authorization=\(credentials)".data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        guard let responseStr = String(data: data, encoding: .utf8) else { return nil }

        // Parse asus_token from response
        // Response is JSON like: {"asus_token":"abcdef123456"}
        if let range = responseStr.range(of: #""asus_token"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let match = responseStr[range]
            if let tokenRange = match.range(of: #":\s*"([^"]+)""#, options: .regularExpression) {
                var tokenStr = String(match[tokenRange])
                tokenStr = tokenStr.replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return tokenStr.isEmpty ? nil : tokenStr
            }
        }
        return nil
    }

    private func fetchData(host: String, token: String) async throws -> String {
        let hooks = ["wanlink()", "cpu_usage(appobj)", "memory_usage(appobj)", "netdev(appobj)"]
        var combined = ""

        for hook in hooks {
            let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: "http://\(cleanHost)/appGet.cgi") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("asusrouter-Android-DUTUtil-1.0.0.245", forHTTPHeaderField: "User-Agent")
            request.setValue("asus_token=\(token)", forHTTPHeaderField: "Cookie")
            request.httpBody = "hook=\(hook)".data(using: .utf8)

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                self.token = nil
                throw URLError(.userAuthenticationRequired)
            }

            if let str = String(data: data, encoding: .utf8) {
                combined += str + "\n"
            }
        }

        return combined
    }

    private func parseResponse(_ response: String) {
        // Parse WAN status — uses function-return format: wanlink_ipaddr(){ return '...';}
        let ip = extractReturnValue(from: response, function: "wanlink_ipaddr") ?? ""
        let gateway = extractReturnValue(from: response, function: "wanlink_gateway") ?? ""
        let dns = extractReturnValue(from: response, function: "wanlink_dns") ?? ""
        let statusStr = extractReturnValue(from: response, function: "wanlink_statusstr") ?? ""
        let statusNum = extractReturnInt(from: response, function: "wanlink_status")
        let wanType = extractReturnValue(from: response, function: "wanlink_type") ?? ""

        wanStatus = WanStatus(
            ip: ip, gateway: gateway, dns: dns,
            status: !statusStr.isEmpty ? statusStr : (statusNum == 1 ? "Connected" : "Disconnected"),
            wanType: wanType
        )

        // Parse CPU usage — JSON format: "cpu_usage":{"cpu1_total":"XX","cpu1_usage":"XX",...}
        parseCpuUsage(from: response)

        // Parse memory usage — JSON format: "memory_usage":{"mem_total":"XXX","mem_free":"XXX",...}
        parseMemoryUsage(from: response)

        // Parse netdev traffic
        var rxBytesPerSec: Double = 0
        var txBytesPerSec: Double = 0
        let now = Date()
        parseNetdev(from: response, now: now, rxOut: &rxBytesPerSec, txOut: &txBytesPerSec)

        // Record snapshot for history charts
        let snapshot = RouterSnapshot(
            timestamp: now,
            cpuPercent: cpuUsage?.average ?? 0,
            memoryPercent: Int(memoryUsage?.usedPercent ?? 0),
            rxBytesPerSec: rxBytesPerSec,
            txBytesPerSec: txBytesPerSec
        )
        history.append(snapshot)
        if history.count > 1440 { history.removeFirst(history.count - 1440) }
        store?.addSnapshot(snapshot)

        // Detect provider changes using the WAN IP
        let currentProvider = wanStatus?.ip ?? ""
        if !currentProvider.isEmpty {
            if let prev = lastSeenProvider, prev != currentProvider {
                let event = ProviderEvent(timestamp: now, from: prev, to: currentProvider)
                providerEvents.append(event)
                store?.addProviderEvent(event)
            }
            lastSeenProvider = currentProvider
        }
    }

    /// Extract integer return value from function-style response
    private func extractReturnInt(from response: String, function: String) -> Int? {
        let pattern = #"function\s+\#(function)\(\)\s*\{\s*return\s+(\d+)\s*;\s*\}"#
        guard let range = response.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(response[range])
        if let numRange = match.range(of: #"return\s+(\d+)"#, options: .regularExpression) {
            let numStr = match[numRange].replacingOccurrences(of: "return", with: "").trimmingCharacters(in: .whitespaces)
            return Int(numStr)
        }
        return nil
    }

    private func parseCpuUsage(from response: String) {
        // Format: "cpu1_total":"CUMULATIVE","cpu1_usage":"CUMULATIVE" — need delta between polls
        var totals: [Int] = []
        var usages: [Int] = []
        for i in 1...4 {
            if let totalStr = extractValue(from: response, key: "cpu\(i)_total"),
               let usageStr = extractValue(from: response, key: "cpu\(i)_usage"),
               let total = Int(totalStr), let usage = Int(usageStr) {
                totals.append(total)
                usages.append(usage)
            }
        }

        guard totals.count >= 2 else { return }

        if !lastCpuTotal.isEmpty && lastCpuTotal.count == totals.count {
            var cores: [Int] = []
            for i in 0..<totals.count {
                let deltaTotal = totals[i] - lastCpuTotal[i]
                let deltaUsage = usages[i] - lastCpuUsage[i]
                let percent = deltaTotal > 0 ? (deltaUsage * 100 / deltaTotal) : 0
                cores.append(min(max(percent, 0), 100))
            }
            while cores.count < 4 { cores.append(0) }
            cpuUsage = CpuUsage(core1: cores[0], core2: cores[1], core3: cores[2], core4: cores[3])
        }

        lastCpuTotal = totals
        lastCpuUsage = usages
    }

    private func parseMemoryUsage(from response: String) {
        // Format: "mem_total":"1048576","mem_free":"380636","mem_used":"667940"
        if let totalStr = extractValue(from: response, key: "mem_total"),
           let total = Int(totalStr) {
            if let usedStr = extractValue(from: response, key: "mem_used"),
               let used = Int(usedStr) {
                memoryUsage = MemoryUsage(totalKB: total, usedKB: used)
            } else if let freeStr = extractValue(from: response, key: "mem_free"),
                      let free = Int(freeStr) {
                memoryUsage = MemoryUsage(totalKB: total, usedKB: total - free)
            }
        }
    }

    private func parseNetdev(from response: String, now: Date, rxOut: inout Double, txOut: inout Double) {
        // netdev response can have various formats. Try to find rx/tx bytes for INTERNET or wan0
        // Common format: "INTERNET":{"tx":"HEX","rx":"HEX",...}
        // Also try decimal values
        let interfaces = ["INTERNET", "wan0"]
        for iface in interfaces {
            if let rxStr = extractValue(from: response, key: "\(iface)_rx") ?? extractNestedValue(from: response, object: iface, key: "rx"),
               let txStr = extractValue(from: response, key: "\(iface)_tx") ?? extractNestedValue(from: response, object: iface, key: "tx") {
                let rxClean = rxStr.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "0x", with: "")
                let txClean = txStr.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "0x", with: "")
                // Try hex first, then decimal
                let rx = Int64(rxClean, radix: 16) ?? Int64(rxClean) ?? 0
                let tx = Int64(txClean, radix: 16) ?? Int64(txClean) ?? 0

                if let prevRx = lastRxBytes, let prevTx = lastTxBytes, let prevTime = lastTrafficTime {
                    let elapsed = now.timeIntervalSince(prevTime)
                    if elapsed > 0 {
                        rxOut = max(Double(rx - prevRx) / elapsed, 0)
                        txOut = max(Double(tx - prevTx) / elapsed, 0)
                    }
                }
                lastRxBytes = rx
                lastTxBytes = tx
                lastTrafficTime = now
                return
            }
        }
    }

    /// Extract a value nested inside an object: "object":{"key":"value",...}
    private func extractNestedValue(from response: String, object: String, key: String) -> String? {
        // Find the object block first
        let objectPattern = #""\#(object)"\s*:\s*\{([^}]*)\}"#
        guard let objRange = response.range(of: objectPattern, options: .regularExpression) else { return nil }
        let objContent = String(response[objRange])
        return extractValue(from: objContent, key: key)
    }

    /// Extract value for key from JSON-like response: "key" : "value"
    private func extractValue(from response: String, key: String) -> String? {
        let pattern = #""\#(key)"\s*:\s*"([^"]*)""#
        guard let range = response.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(response[range])
        // Get the value between the last pair of quotes
        if let lastQuote = match.lastIndex(of: "\""),
           let secondLastQuote = match[match.startIndex..<lastQuote].lastIndex(of: "\"") {
            let value = match[match.index(after: secondLastQuote)..<lastQuote]
            return String(value)
        }
        return nil
    }

    /// Extract return value from function-style response: function name(){ return 'value';}
    private func extractReturnValue(from response: String, function: String) -> String? {
        // Match: function name() { return 'value'; } or name(){ return 'value';}
        let pattern = #"(?:function\s+)?\#(function)\(\)\s*\{\s*return\s+'([^']*)'\s*;\s*\}"#
        guard let range = response.range(of: pattern, options: .regularExpression) else { return nil }
        let match = String(response[range])
        if let start = match.lastIndex(of: "'") {
            let beforeLast = match[match.startIndex..<start]
            if let innerStart = beforeLast.lastIndex(of: "'") {
                return String(match[match.index(after: innerStart)..<start])
            }
        }
        return nil
    }
}
