import SwiftUI

@main
struct WiFiMonitorApp: App {
    let pingService = PingService()
    let pingStore = PingStore()
    let routerService = RouterService()
    let routerStore = RouterStore()
    let wifiService = WiFiService()
    let wifiStore = WiFiStore()
    let profileStore = NetworkProfileStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pingService)
                .environment(pingStore)
                .environment(routerService)
                .environment(routerStore)
                .environment(wifiService)
                .environment(wifiStore)
                .environment(profileStore)
        }

        Settings {
            SettingsView()
                .environment(routerService)
                .environment(routerStore)
                .environment(wifiService)
                .environment(profileStore)
        }
    }
}
