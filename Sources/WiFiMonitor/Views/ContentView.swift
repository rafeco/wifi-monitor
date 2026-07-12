import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PingService.self) private var pingService
    @Environment(PingStore.self) private var pingStore
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @Environment(WiFiService.self) private var wifiService
    @Environment(WiFiStore.self) private var wifiStore
    @Environment(NetworkProfileStore.self) private var profileStore
    @State private var selectedDate = Date()

    // Window controls: collapse to just the top bar, and float above others.
    @State private var collapsed = false
    @AppStorage("stayOnTop") private var stayOnTop = false
    @State private var window: NSWindow?
    @State private var barSize: CGSize = CGSize(width: 760, height: 90)
    @State private var expandedContentHeight: CGFloat = 560
    @State private var expandedWidth: CGFloat = 760

    /// Router monitoring is shown only when the current network has an enabled profile.
    private var routerMonitored: Bool {
        guard let ssid = wifiService.currentSSID else { return false }
        return profileStore.profile(for: ssid)?.routerEnabled ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned top bar — stays put while the content below scrolls, and
            // is all that remains when the window is collapsed.
            HStack(alignment: .center, spacing: 12) {
                StatusBarView(selectedDate: selectedDate)
                windowControls
            }
            .padding()
            // When collapsed, adopt the bar's intrinsic width so the window can
            // shrink around it instead of staying full-width.
            .fixedSize(horizontal: collapsed, vertical: false)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { barSize = proxy.size }
                        .onChange(of: proxy.size) { _, size in barSize = size }
                }
            )

            Divider()

            if !collapsed {
            ScrollView {
                VStack(spacing: 0) {
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
            }
        }
        .frame(minWidth: collapsed ? nil : 700, minHeight: collapsed ? nil : 500)
        .background(WindowAccessor(window: $window))
        .onChange(of: collapsed) { _, nowCollapsed in
            // Capture the expanded size before shrinking so we can restore it.
            if nowCollapsed, let w = window {
                expandedWidth = w.frame.width
                expandedContentHeight = w.contentLayoutRect.height
            }
            applyWindowSize()
        }
        .onChange(of: stayOnTop) { _, _ in applyWindowLevel() }
        // While collapsed, keep the window fitted to the bar as its size changes.
        .onChange(of: barSize) { _, _ in if collapsed { applyWindowSize() } }
        .onAppear {
            pingService.start(store: pingStore)
            wifiService.start(store: wifiStore)
            // Always poll; RouterService itself decides per-network whether
            // there's anything to monitor.
            routerService.start(store: routerStore, profiles: profileStore)
            if let ssid = wifiService.currentSSID { profileStore.discover(ssid: ssid) }
            applyWindowLevel()
        }
        // Record the network as soon as its name is known. The SSID may arrive
        // after launch (Location permission resolves asynchronously), so react
        // to it here rather than only discovering once on appear.
        .onChange(of: wifiService.currentSSID) { _, ssid in
            if let ssid { profileStore.discover(ssid: ssid) }
        }
    }

    private var windowControls: some View {
        HStack(spacing: 10) {
            Button {
                stayOnTop.toggle()
            } label: {
                Image(systemName: stayOnTop ? "pin.fill" : "pin")
            }
            .help(stayOnTop ? "Stop floating above other windows" : "Keep window on top")

            Button {
                collapsed.toggle()
            } label: {
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
            }
            .help(collapsed ? "Expand" : "Collapse to the status bar")
        }
        .buttonStyle(.borderless)
        .font(.body)
        .foregroundStyle(.secondary)
    }

    private func applyWindowLevel() {
        window?.level = stayOnTop ? .floating : .normal
    }

    /// Resize the window to the top bar when collapsed (locked, non-resizable),
    /// or back to the remembered expanded size. The top-left corner is kept
    /// anchored so the title bar doesn't jump.
    private func applyWindowSize() {
        guard let window else { return }
        let chrome = window.frame.height - window.contentLayoutRect.height

        let targetWidth: CGFloat
        let targetContentHeight: CGFloat
        if collapsed {
            targetWidth = barSize.width
            targetContentHeight = barSize.height
            window.styleMask.remove(.resizable)
        } else {
            targetWidth = expandedWidth
            targetContentHeight = expandedContentHeight
            window.styleMask.insert(.resizable)
        }

        var frame = window.frame
        let top = frame.maxY
        let left = frame.minX
        frame.size = NSSize(width: targetWidth, height: targetContentHeight + chrome)
        frame.origin.x = left
        frame.origin.y = top - frame.size.height
        window.setFrame(frame, display: true, animate: true)
    }
}

/// Bridges to the underlying NSWindow so we can control level and size.
private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
