import Foundation

/// Whether this network's router works with our (ASUS/ASUSWRT-only) integration.
/// `unknown` until probed; `unsupported` means we reached the gateway and it
/// didn't look like ASUS.
enum RouterCompatibility: String, Codable {
    case unknown
    case supported
    case unsupported
}

/// Per-WiFi-network router configuration, keyed by SSID. The password is not
/// part of this struct — it lives in the Keychain (see `Keychain`), looked up
/// by the same SSID.
struct NetworkProfile: Codable, Identifiable {
    var id: String { ssid }
    let ssid: String
    var routerEnabled: Bool
    var autoDetectIP: Bool
    var routerIP: String
    var username: String
    var compatibility: RouterCompatibility

    init(ssid: String, routerEnabled: Bool = false, autoDetectIP: Bool = true, routerIP: String = "192.168.50.1", username: String = "admin", compatibility: RouterCompatibility = .unknown) {
        self.ssid = ssid
        self.routerEnabled = routerEnabled
        self.autoDetectIP = autoDetectIP
        self.routerIP = routerIP
        self.username = username
        self.compatibility = compatibility
    }

    // Custom decoding so profiles saved before `compatibility` existed still load.
    private enum CodingKeys: String, CodingKey {
        case ssid, routerEnabled, autoDetectIP, routerIP, username, compatibility
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ssid = try c.decode(String.self, forKey: .ssid)
        routerEnabled = try c.decode(Bool.self, forKey: .routerEnabled)
        autoDetectIP = try c.decode(Bool.self, forKey: .autoDetectIP)
        routerIP = try c.decode(String.self, forKey: .routerIP)
        username = try c.decode(String.self, forKey: .username)
        compatibility = try c.decodeIfPresent(RouterCompatibility.self, forKey: .compatibility) ?? .unknown
    }
}

/// Stores the set of network profiles as JSON in Application Support, and
/// brokers passwords through the Keychain. Auto-discovers networks as they're
/// seen (added disabled) and migrates the old single global router config.
@Observable
final class NetworkProfileStore {
    private(set) var profiles: [NetworkProfile] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("WiFiMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("network-profiles.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        decoder = JSONDecoder()

        load()
        migrateLegacyConfigIfNeeded()
    }

    func profile(for ssid: String) -> NetworkProfile? {
        profiles.first { $0.ssid == ssid }
    }

    /// Insert or replace a profile, then persist.
    func upsert(_ profile: NetworkProfile) {
        if let index = profiles.firstIndex(where: { $0.ssid == profile.ssid }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending }
        save()
    }

    /// Record a newly seen network so it shows up in Settings. No-op if it
    /// already exists. New networks start with monitoring disabled.
    func discover(ssid: String) {
        guard !ssid.isEmpty, profile(for: ssid) == nil else { return }
        upsert(NetworkProfile(ssid: ssid))
    }

    func remove(ssid: String) {
        profiles.removeAll { $0.ssid == ssid }
        Keychain.deletePassword(ssid: ssid)
        save()
    }

    // MARK: - Passwords (Keychain)

    func password(for ssid: String) -> String? {
        Keychain.password(ssid: ssid)
    }

    func setPassword(_ password: String, for ssid: String) {
        Keychain.setPassword(password, ssid: ssid)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        profiles = (try? decoder.decode([NetworkProfile].self, from: data)) ?? []
    }

    private func save() {
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// One-time migration of the pre-profiles global router config. Only runs
    /// when a home network was learned (we need an SSID to key the profile on);
    /// the old password is moved into the Keychain and cleared from UserDefaults.
    private func migrateLegacyConfigIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "profilesMigrated") else { return }

        let homeSSID = defaults.string(forKey: "routerHomeSSID") ?? ""
        if !homeSSID.isEmpty, profile(for: homeSSID) == nil {
            var profile = NetworkProfile(ssid: homeSSID)
            profile.routerEnabled = defaults.object(forKey: "routerEnabled") as? Bool ?? true
            profile.autoDetectIP = defaults.object(forKey: "routerAutoDetectIP") as? Bool ?? true
            profile.routerIP = defaults.string(forKey: "routerIP") ?? "192.168.50.1"
            profile.username = defaults.string(forKey: "routerUsername") ?? "admin"
            upsert(profile)

            if let oldPassword = defaults.string(forKey: "routerPassword"), !oldPassword.isEmpty {
                Keychain.setPassword(oldPassword, ssid: homeSSID)
                defaults.removeObject(forKey: "routerPassword")
            }
        }

        defaults.set(true, forKey: "profilesMigrated")
    }
}
