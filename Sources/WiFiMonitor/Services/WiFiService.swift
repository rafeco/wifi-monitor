import Foundation
import CoreWLAN

extension Notification.Name {
    /// Posted when the associated WiFi network (SSID) changes, so other
    /// services can re-baseline network-relative state (ISP cache, bufferbloat
    /// throughput peak) instead of carrying stale data across networks.
    static let wifiNetworkChanged = Notification.Name("wifiNetworkChanged")
}

struct WiFiSnapshot: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let rssi: Int
    let noise: Int
    let snr: Int
    let txRate: Double
    let channel: Int
    let band: String

    init(id: UUID = UUID(), timestamp: Date = Date(), rssi: Int, noise: Int, txRate: Double, channel: Int, band: String) {
        self.id = id
        self.timestamp = timestamp
        self.rssi = rssi
        self.noise = noise
        self.snr = rssi - noise
        self.txRate = txRate
        self.channel = channel
        self.band = band
    }

    var signalQuality: String {
        if rssi > -50 { return "Excellent" }
        if rssi > -60 { return "Good" }
        if rssi > -70 { return "Fair" }
        if rssi > -80 { return "Weak" }
        return "Poor"
    }
}

@Observable
final class WiFiService {
    var lastSnapshot: WiFiSnapshot?
    var isRunning: Bool = false

    /// Name of the currently associated network, or nil if unknown. (macOS
    /// returns nil unless the app has Location Services authorization.)
    var currentSSID: String?
    /// When the app last observed the network change. Consumers scope
    /// network-relative baselines (e.g. throughput peak) to samples after this.
    var lastNetworkChange: Date = .distantPast

    private var timer: Timer?
    private var store: WiFiStore?
    private let locationPermission = LocationPermission()

    func start(store: WiFiStore) {
        guard !isRunning else { return }
        self.store = store
        isRunning = true

        // Needed for iface.ssid() to return a name on macOS 14+.
        locationPermission.request()

        sample()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    private func sample() {
        guard let iface = CWWiFiClient.shared().interface() else { return }

        let rssi = iface.rssiValue()
        // 0 dBm means the interface has no valid reading (e.g., momentary disconnection)
        guard rssi != 0 else { return }
        let noise = iface.noiseMeasurement()
        let txRate = iface.transmitRate()
        let channel = iface.wlanChannel()?.channelNumber ?? 0

        let bandRaw = iface.wlanChannel()?.channelBand ?? .bandUnknown
        let band: String
        switch bandRaw {
        case .band2GHz: band = "2.4 GHz"
        case .band5GHz: band = "5 GHz"
        case .band6GHz: band = "6 GHz"
        default: band = "Unknown"
        }

        updateNetworkIdentity(iface.ssid())

        let snapshot = WiFiSnapshot(
            rssi: rssi, noise: noise, txRate: txRate,
            channel: channel, band: band
        )
        lastSnapshot = snapshot
        store?.add(snapshot)
    }

    /// Track the associated SSID and announce genuine network switches. Ignores
    /// nil/empty readings (transient disconnects, or missing Location
    /// permission) so we don't fire spurious changes, and stays silent on the
    /// very first observation since there's no prior network to switch from.
    private func updateNetworkIdentity(_ ssid: String?) {
        guard let ssid, !ssid.isEmpty else { return }
        guard let previous = currentSSID else {
            currentSSID = ssid
            return
        }
        guard ssid != previous else { return }
        currentSSID = ssid
        lastNetworkChange = Date()
        NotificationCenter.default.post(name: .wifiNetworkChanged, object: nil)
    }
}

@Observable
final class WiFiStore {
    /// Incremented on each add to trigger SwiftUI re-renders
    private(set) var updateCount: Int = 0

    private let storageDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        storageDir = appSupport.appendingPathComponent("WiFiMonitor/wifi", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func add(_ snapshot: WiFiSnapshot) {
        let url = fileURL(for: snapshot.timestamp)
        var existing = load(for: snapshot.timestamp)
        existing.append(snapshot)
        if let data = try? encoder.encode(existing) {
            try? data.write(to: url, options: .atomic)
        }
        updateCount += 1
    }

    func snapshots(for date: Date) -> [WiFiSnapshot] {
        load(for: date)
    }

    private func load(for date: Date) -> [WiFiSnapshot] {
        let url = fileURL(for: date)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([WiFiSnapshot].self, from: data)) ?? []
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func fileURL(for date: Date) -> URL {
        storageDir.appendingPathComponent("wifi-\(Self.dateFormatter.string(from: date)).json")
    }
}
