import SwiftUI

@main
struct WiFiMonitorApp: App {
    let pingService = PingService()
    let pingStore = PingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pingService)
                .environment(pingStore)
        }
    }
}
