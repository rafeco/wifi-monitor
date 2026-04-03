import SwiftUI

@main
struct WiFiMonitorApp: App {
    let pingService = PingService()
    let pingStore = PingStore()
    let routerService = RouterService()
    let routerStore = RouterStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pingService)
                .environment(pingStore)
                .environment(routerService)
                .environment(routerStore)
        }

        Settings {
            SettingsView()
                .environment(routerService)
                .environment(routerStore)
        }
    }
}
