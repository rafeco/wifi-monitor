import SwiftUI

struct ContentView: View {
    @Environment(PingService.self) private var pingService
    @Environment(PingStore.self) private var pingStore
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @Environment(WiFiService.self) private var wifiService
    @Environment(WiFiStore.self) private var wifiStore
    @Environment(NetworkProfileStore.self) private var profileStore
    @State private var selectedDate = Date()

    /// Router monitoring is shown only when the current network has an enabled profile.
    private var routerMonitored: Bool {
        guard let ssid = wifiService.currentSSID else { return false }
        return profileStore.profile(for: ssid)?.routerEnabled ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StatusBarView(selectedDate: selectedDate)
                    .padding()

                Divider()

                DayNavigationView(selectedDate: $selectedDate)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                VStack(spacing: 16) {
                    // -- Connectivity Section --
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Latency", systemImage: "network")
                                .font(.headline)
                            LatencyChartView(selectedDate: selectedDate)
                                .frame(height: 200)
                        }
                    }

                    GroupBox {
                        WiFiSignalChartView(selectedDate: selectedDate)
                    }

                    // -- Router Section (only when this network is monitored) --
                    if routerMonitored {
                        Divider()

                        Text("Router")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        RouterSectionView()
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            pingService.start(store: pingStore)
            wifiService.start(store: wifiStore)
            // Always poll; RouterService itself decides per-network whether
            // there's anything to monitor.
            routerService.start(store: routerStore, profiles: profileStore)
            if let ssid = wifiService.currentSSID { profileStore.discover(ssid: ssid) }
        }
        // Record the network as soon as its name is known. The SSID may arrive
        // after launch (Location permission resolves asynchronously), so react
        // to it here rather than only discovering once on appear.
        .onChange(of: wifiService.currentSSID) { _, ssid in
            if let ssid { profileStore.discover(ssid: ssid) }
        }
    }
}

struct DayNavigationView: View {
    @Binding var selectedDate: Date

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        HStack {
            Button(action: { moveDay(by: -1) }) {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(selectedDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.headline)

            if !isToday {
                Button("Today") {
                    selectedDate = Date()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            Button(action: { moveDay(by: 1) }) {
                Image(systemName: "chevron.right")
            }
            .disabled(isToday)
        }
    }

    private func moveDay(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }
}
