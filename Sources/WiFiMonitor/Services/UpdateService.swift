import AppKit
import Observation

/// Stable numeric release tags, compared component by component (1.10 > 1.9).
struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ string: String) {
        let value = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        components = numbers
    }

    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let a = index < lhs.components.count ? lhs.components[index] : 0
            let b = index < rhs.components.count ? rhs.components[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}

struct AppRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable { let name: String; let state: String }

    var version: ReleaseVersion? { ReleaseVersion(tag_name) }
    var isInstallable: Bool {
        !draft && !prerelease && version != nil && assets.contains { $0.name == "WiFiMonitor.zip" && $0.state == "uploaded" }
    }

    var downloadPage: URL {
        URL(string: "https://github.com/rafeco/wifi-monitor/releases/tag/\(tag_name)")!
    }
}

@MainActor
@Observable
final class UpdateService {
    private(set) var availableRelease: AppRelease?
    private(set) var isChecking = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentVersion: String?
    @ObservationIgnored private let fetch: () async throws -> (Data, URLResponse)
    private static let nextCheckKey = "updates.nextCheck"
    private static let skippedKey = "updates.skippedVersion"

    init(defaults: UserDefaults = .standard,
         currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         fetch: @escaping () async throws -> (Data, URLResponse) = {
             var request = URLRequest(url: URL(string: "https://api.github.com/repos/rafeco/wifi-monitor/releases/latest")!)
             request.timeoutInterval = 15
             request.cachePolicy = .reloadIgnoringLocalCacheData
             request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
             request.setValue("WiFiMonitor", forHTTPHeaderField: "User-Agent")
             return try await URLSession.shared.data(for: request)
         }) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    func start() {
        guard timer == nil else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func dismiss() { availableRelease = nil }

    func skip() {
        if let version = availableRelease?.tag_name { defaults.set(version, forKey: Self.skippedKey) }
        dismiss()
    }

    func check(manual: Bool = false) async {
        guard !isChecking else { return }
        if !manual, let next = defaults.object(forKey: Self.nextCheckKey) as? Date, next > Date() { return }
        guard let currentVersion, let installed = ReleaseVersion(currentVersion) else {
            if manual { showMessage("Version unavailable", "Update checks require a bundled release of WiFi Monitor.") }
            return
        }
        isChecking = true
        defer { isChecking = false }
        // Failed background checks retry quietly in an hour, including after relaunch.
        defaults.set(Date().addingTimeInterval(3600), forKey: Self.nextCheckKey)
        do {
            let (data, response) = try await fetch()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            guard release.isInstallable, let version = release.version else { throw URLError(.cannotParseResponse) }
            defaults.set(Date().addingTimeInterval(86400), forKey: Self.nextCheckKey)
            guard version > installed else {
                availableRelease = nil
                if manual { showMessage("You’re up to date", "WiFi Monitor \(currentVersion) is the latest available version.") }
                return
            }
            guard manual || defaults.string(forKey: Self.skippedKey) != release.tag_name else { return }
            availableRelease = release
            if manual {
                let alert = NSAlert()
                alert.messageText = "WiFi Monitor \(release.tag_name) is available"
                alert.informativeText = "You’re running \(currentVersion). Download the new version from GitHub and replace the app in Applications."
                alert.addButton(withTitle: "Download Update")
                alert.addButton(withTitle: "Later")
                alert.addButton(withTitle: "Skip This Version")
                switch alert.runModal() {
                case .alertFirstButtonReturn: NSWorkspace.shared.open(release.downloadPage)
                case .alertThirdButtonReturn: skip()
                default: dismiss()
                }
            }
        } catch {
            if manual { showMessage("Couldn’t check for updates", "Please check your internet connection and try again later.") }
        }
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
