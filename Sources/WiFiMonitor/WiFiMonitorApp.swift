import SwiftUI
import AppKit

@main
struct WiFiMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private static let repoURL = URL(string: "https://github.com/rafeco/wifi-monitor")!
    let pingService = PingService()
    let pingStore = PingStore()
    let routerService = RouterService()
    let routerStore = RouterStore()
    let wifiService = WiFiService()
    let wifiStore = WiFiStore()
    let profileStore = NetworkProfileStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .onAppear {
                    appDelegate.reopenMainWindow = { openWindow(id: "main") }
                }
                .environment(pingService)
                .environment(pingStore)
                .environment(routerService)
                .environment(routerStore)
                .environment(wifiService)
                .environment(wifiStore)
                .environment(profileStore)
        }
        .commands {
            // Replace the default About item with one that links to the repo.
            CommandGroup(replacing: .appInfo) {
                Button("About WiFi Monitor") { showAboutPanel() }
            }
        }

        Settings {
            SettingsView()
                .environment(routerService)
                .environment(routerStore)
                .environment(wifiService)
                .environment(profileStore)
        }
    }

    /// Standard About panel (app name/version/icon from Info.plist) with a
    /// clickable GitHub link in the credits field.
    private func showAboutPanel() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "github.com/rafeco/wifi-monitor",
            attributes: [
                .link: Self.repoURL,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph,
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var reopenMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Let AppKit restore minimized windows instead of creating another one.
        if sender.windows.contains(where: { $0.isMiniaturized }) { return true }
        guard !flag, let reopenMainWindow else { return true }
        reopenMainWindow()
        return false
    }
}
