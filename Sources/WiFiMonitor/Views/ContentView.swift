import SwiftUI

struct ContentView: View {
    @Environment(PingService.self) private var pingService
    @Environment(PingStore.self) private var pingStore
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @State private var selectedDate = Date()

    var body: some View {
        TabView {
            connectivityTab
                .tabItem {
                    Label("Connectivity", systemImage: "wifi")
                }

            RouterView()
                .tabItem {
                    Label("Router", systemImage: "wifi.router")
                }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            pingService.start(store: pingStore)
            routerService.start(store: routerStore)
        }
    }

    private var connectivityTab: some View {
        VStack(spacing: 0) {
            StatusBarView(selectedDate: selectedDate)
                .padding()

            Divider()

            DayNavigationView(selectedDate: $selectedDate)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            LatencyChartView(selectedDate: selectedDate)
                .padding()
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
