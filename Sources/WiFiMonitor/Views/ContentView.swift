import SwiftUI

struct ContentView: View {
    @Environment(PingService.self) private var pingService
    @Environment(PingStore.self) private var pingStore
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @Environment(WiFiService.self) private var wifiService
    @Environment(WiFiStore.self) private var wifiStore
    @AppStorage("routerEnabled") private var routerEnabled = true
    @State private var selectedDate = Date()

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

                    // -- Router Section (conditional) --
                    if routerEnabled {
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
            if routerEnabled {
                routerService.start(store: routerStore)
            }
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
