import Foundation

@main
struct UpdateTests {
    @MainActor
    static func main() async throws {
        func version(_ text: String) -> ReleaseVersion { ReleaseVersion(text)! }
        assert(version("v1.10") > version("1.9"))
        assert(version("1.7.1") > version("1.7"))
        assert(version("1.7") == version("1.7.0"))
        assert(version("2.0") > version("1.99"))
        for invalid in ["", "v", "1..7", "1.8-beta", "banana", "-1.0", "1.0/elsewhere"] {
            assert(ReleaseVersion(invalid) == nil)
        }

        let suite = "WiFiMonitor.UpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        var tag = "v1.10"
        var status = 200
        var prerelease = false
        var draft = false
        var asset = "WiFiMonitor.zip"
        let service = UpdateService(defaults: defaults, currentVersion: "1.9") {
            calls += 1
            let data = try JSONSerialization.data(withJSONObject: [
                "tag_name": tag, "draft": draft, "prerelease": prerelease,
                "assets": [["name": asset, "state": "uploaded"]]
            ])
            return (data, HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        func makeDue() { defaults.removeObject(forKey: "updates.nextCheck") }
        await service.check()
        assert(service.availableRelease?.tag_name == "v1.10")
        assert(service.availableRelease?.downloadPage.absoluteString == "https://github.com/rafeco/wifi-monitor/releases/tag/v1.10")
        await service.check()
        assert(calls == 1, "Successful checks must be throttled")
        service.dismiss()
        assert(service.availableRelease == nil)
        makeDue()
        await service.check()
        assert(service.availableRelease != nil, "Dismissed release returns at next daily check")
        service.skip()
        makeDue()
        await service.check()
        assert(service.availableRelease == nil, "Skipped version must stay hidden")
        tag = "v1.11"
        makeDue()
        await service.check()
        assert(service.availableRelease?.tag_name == tag, "A newer release must not inherit skip")
        service.dismiss()
        tag = "v1.8"
        makeDue()
        await service.check()
        assert(service.availableRelease == nil, "Never offer downgrade")
        tag = "v1.9.0"
        makeDue()
        await service.check()
        assert(service.availableRelease == nil, "Equivalent versions aren't updates")
        tag = "v2.0"
        prerelease = true
        makeDue()
        await service.check()
        assert(service.availableRelease == nil)
        prerelease = false
        draft = true
        makeDue()
        await service.check()
        assert(service.availableRelease == nil)
        draft = false
        asset = "source.zip"
        makeDue()
        await service.check()
        assert(service.availableRelease == nil, "Do not advertise releases without an app download")
        asset = "WiFiMonitor.zip"
        status = 403
        makeDue()
        await service.check()
        assert(service.availableRelease == nil && !service.isChecking)
        let count = calls
        await service.check()
        assert(calls == count, "Failed checks should back off")
        let next = defaults.object(forKey: "updates.nextCheck") as! Date
        assert(next.timeIntervalSinceNow > 3500 && next.timeIntervalSinceNow <= 3600)
        let unbundled = UpdateService(defaults: defaults, currentVersion: nil) {
            fatalError("Unbundled build must not request a release")
        }
        makeDue()
        await unbundled.check()
        print("Update checks passed")
    }
}
