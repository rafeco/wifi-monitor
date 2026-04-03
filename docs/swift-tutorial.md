# WiFi Monitor: A Swift & SwiftUI Tutorial

This document walks through the entire WiFi Monitor app, explaining every Swift and SwiftUI concept used. It's written for someone who can program but hasn't worked with Swift or SwiftUI before.

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Swift Basics Used in This App](#2-swift-basics-used-in-this-app)
3. [The App Entry Point](#3-the-app-entry-point)
4. [Data Models](#4-data-models)
5. [Services: Background Work](#5-services-background-work)
6. [Persistence: Storing Data as JSON](#6-persistence-storing-data-as-json)
7. [Views: Building the UI](#7-views-building-the-ui)
8. [Charts: Visualizing Data](#8-charts-visualizing-data)
9. [Environment: Dependency Injection](#9-environment-dependency-injection)
10. [Settings and UserDefaults](#10-settings-and-userdefaults)
11. [Networking: URLSession](#11-networking-urlsession)
12. [Shelling Out: Process](#12-shelling-out-process)
13. [CoreWLAN: Reading WiFi Info](#13-corewlan-reading-wifi-info)
14. [How It All Fits Together](#14-how-it-all-fits-together)

---

## 1. Project Structure

The app is built as a **Swift Package Manager (SPM) executable** — no Xcode project file needed. Everything is defined in `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WiFiMonitor",
    platforms: [.macOS(.v14)],   // Requires macOS 14 (Sonoma) or later
    targets: [
        .executableTarget(
            name: "WiFiMonitor",
            path: "Sources/WiFiMonitor"
        )
    ]
)
```

**Key points:**
- `platforms: [.macOS(.v14)]` — Sets the minimum macOS version. We need 14+ for Swift Charts and the `@Observable` macro.
- `.executableTarget` — This builds a runnable binary, not a library. The binary is the app itself.
- No external dependencies — everything uses Apple's built-in frameworks (SwiftUI, Charts, CoreWLAN, Foundation).

**Build and run:** `swift build && swift run WiFiMonitor`

The file layout follows a standard pattern:

```
Sources/WiFiMonitor/
├── WiFiMonitorApp.swift       ← App entry point (@main)
├── Models/                    ← Data structures
├── Services/                  ← Background work (timers, networking, persistence)
├── Views/                     ← SwiftUI views (what you see on screen)
└── Utilities/                 ← Small helper functions
```

---

## 2. Swift Basics Used in This App

### Structs vs Classes

Swift has two main ways to define types:

```swift
struct PingRecord { ... }    // Value type — copied when passed around
class PingService { ... }    // Reference type — shared when passed around
```

**Rule of thumb in this app:** Data models are `struct`s (lightweight, copyable). Services are `class`es (because they hold mutable state and are shared across the app).

### Optionals

Swift uses `?` to represent values that might be missing:

```swift
var latencyMs: Double?     // Either a Double or nil (no value)
```

You unwrap optionals safely with `if let` or `guard let`:

```swift
if let latency = record.latencyMs {
    // latency is a regular Double here, guaranteed non-nil
    print("Latency: \(latency) ms")
}

guard let url = URL(string: "http://...") else { return }
// url is guaranteed non-nil from here on
```

The `??` operator provides a default: `password ?? ""` means "use password, or empty string if nil."

### Closures

Closures are anonymous functions, used heavily for callbacks:

```swift
Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
    self?.performPing()
}
```

`[weak self]` prevents a memory leak — without it, the timer would keep the service alive forever (a "retain cycle").

### Computed Properties

Properties that are calculated rather than stored:

```swift
var signalQuality: String {
    if rssi > -50 { return "Excellent" }
    if rssi > -60 { return "Good" }
    // ...
}
```

These look like regular properties but run code each time they're accessed.

### Protocols (Codable, Identifiable)

Protocols are like interfaces. Two common ones:

```swift
struct PingRecord: Codable, Identifiable {
    let id: UUID           // Required by Identifiable
    // ...
}
```

- **`Codable`** — The compiler auto-generates JSON encoding/decoding for all properties.
- **`Identifiable`** — Requires an `id` property. SwiftUI uses this to efficiently track items in lists and charts.

---

## 3. The App Entry Point

**File: `WiFiMonitorApp.swift`**

Every SwiftUI app starts with a struct marked `@main`:

```swift
@main
struct WiFiMonitorApp: App {
    let pingService = PingService()
    let pingStore = PingStore()
    let routerService = RouterService()
    let routerStore = RouterStore()
    let wifiService = WiFiService()
    let wifiStore = WiFiStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(pingService)
                .environment(pingStore)
                // ... etc
        }

        Settings {
            SettingsView()
                .environment(routerService)
                .environment(routerStore)
        }
    }
}
```

**What's happening:**

- `@main` tells Swift this is the entry point (like `main()` in C).
- All six services/stores are created once here and live for the app's lifetime.
- `WindowGroup` defines the main window. `Settings` defines the Preferences window (opened with Cmd+,).
- `.environment(...)` injects each service into the view hierarchy (more on this in [section 9](#9-environment-dependency-injection)).

**`some Scene`** — The `some` keyword means "this returns a specific type, but I don't want to spell it out." SwiftUI uses this everywhere because the actual types are complex compiler-generated names.

---

## 4. Data Models

**File: `Models/PingRecord.swift`**

```swift
struct PingRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let latencyMs: Double?      // nil means timeout
    let success: Bool
    let host: String
    let connection: String?     // ISP name, e.g., "AS29852 Honest Networks, LLC"
}
```

This is a plain data container. Because it conforms to `Codable`, Swift can automatically convert it to/from JSON:

```json
{"id":"53FAC15C-...", "timestamp":"2026-04-03T11:55:35Z", "latencyMs":12.5, "success":true, "host":"1.1.1.1", "connection":"AS29852 Honest Networks, LLC"}
```

The `connection` field stores the raw ISP string from ipinfo.io. A helper function strips the "AS" prefix for display:

```swift
func shortConnectionName(_ connection: String?) -> String {
    guard let connection else { return "Unknown" }
    if connection.prefix(2) == "AS",
       let spaceIndex = connection.firstIndex(of: " ") {
        return String(connection[connection.index(after: spaceIndex)...])
    }
    return connection
}
// "AS29852 Honest Networks, LLC" → "Honest Networks, LLC"
```

**Computed properties** add behavior without storing extra data:

```swift
var statusColor: Color {
    guard success, let latency = latencyMs else { return .red }
    if latency <= 50 { return .green }
    if latency <= 200 { return .yellow }
    return .orange
}
```

---

## 5. Services: Background Work

Services are `@Observable` classes that run timers, do network requests, and hold live state that the UI reacts to.

### The @Observable Macro

**File: `Services/PingService.swift`**

```swift
@Observable
final class PingService {
    var lastLatency: Double?
    var lastSuccess: Bool = true
    var lastConnection: String?
    var isRunning: Bool = false
    // ...
}
```

`@Observable` (new in macOS 14 / Swift 5.9) makes every `var` property automatically notify SwiftUI when it changes. When `lastLatency` changes, any view reading it re-renders. This replaced the older `ObservableObject` + `@Published` pattern.

`final` means the class can't be subclassed — a minor performance optimization.

### Timer Pattern

All three services (Ping, WiFi, Router) follow the same pattern:

```swift
func start(store: PingStore) {
    guard !isRunning else { return }    // Prevent double-start
    self.store = store
    isRunning = true

    performPing()                        // Do it once immediately

    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
        self?.performPing()              // Then every 30 seconds
    }
    RunLoop.current.add(timer!, forMode: .common)  // Keep firing during UI interaction
}
```

**`RunLoop.current.add(timer!, forMode: .common)`** — By default, timers pause when you're scrolling or dragging in the UI. Adding to `.common` mode keeps them firing.

### Background Thread Work

Ping execution happens off the main thread to avoid freezing the UI:

```swift
private func performPing() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
        let result = Self.executePing(host: "1.1.1.1")  // Slow work (network I/O)
        DispatchQueue.main.async {
            self?.lastLatency = result.latency            // Update UI on main thread
            self?.lastSuccess = result.success
        }
    }
}
```

**Golden rule:** UI updates must happen on the main thread. `DispatchQueue.main.async` ensures this.

`[weak self]` prevents the closure from keeping the service alive if it's deallocated. `self?` means "do nothing if self is gone."

---

## 6. Persistence: Storing Data as JSON

**File: `Services/PingStore.swift`**

The app stores all data as JSON files — one file per day, in `~/Library/Application Support/WiFiMonitor/`.

### Writing

```swift
func add(_ record: PingRecord) {
    records.append(record)               // Keep in memory for today
    save(record)                         // Also write to disk
}

private func save(_ record: PingRecord) {
    let url = fileURL(for: record.timestamp)
    var existing = loadRecords(for: record.timestamp)  // Read current file
    existing.append(record)                             // Add new record
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601             // "2026-04-03T11:55:35Z"
    if let data = try? encoder.encode(existing) {
        try? data.write(to: url, options: .atomic)      // Write atomically (safe)
    }
}
```

**`.atomic`** means "write to a temp file first, then rename." This prevents corruption if the app crashes mid-write.

**`try?`** silently ignores errors. For a personal app this is fine — in production you'd use `do/catch`.

### Reading

```swift
private func loadRecords(for date: Date) -> [PingRecord] {
    let url = fileURL(for: date)
    guard let data = try? Data(contentsOf: url) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([PingRecord].self, from: data)) ?? []
}
```

`[PingRecord].self` tells the decoder "this JSON is an array of PingRecords." The `?? []` means "if decoding fails, return an empty array."

### File Naming

```swift
private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private func fileURL(for date: Date) -> URL {
    let name = Self.dateFormatter.string(from: date)
    return storageDir.appendingPathComponent("\(name).json")
}
// → "2026-04-03.json"
```

`DateFormatter` is expensive to create, so it's a `static let` — created once and reused.

---

## 7. Views: Building the UI

SwiftUI builds UI declaratively — you describe what you want, not how to draw it.

### Basic View Structure

**File: `Views/ContentView.swift`**

```swift
struct ContentView: View {
    @Environment(PingService.self) private var pingService
    @State private var selectedDate = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StatusBarView(selectedDate: selectedDate)
                    .padding()
                Divider()
                // ... more views
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            pingService.start(store: pingStore)
        }
    }
}
```

**Key SwiftUI concepts:**

- **`View` protocol** — Every UI element is a struct conforming to `View` with a `body` property.
- **`VStack`** — Stacks children vertically. `HStack` stacks horizontally. `ZStack` stacks in depth (front to back).
- **`.padding()`** — Adds space around a view. Chainable modifiers are how you style things in SwiftUI.
- **`.onAppear`** — Runs code when the view first appears on screen.
- **`@State`** — A property that, when changed, re-renders the view. Owned by this view.

### Conditional Rendering

```swift
if routerEnabled {
    Text("Router")
        .font(.title3.bold())
    RouterSectionView()
}
```

SwiftUI views are just Swift code — you can use `if`, `for`, etc. directly in the body.

### GroupBox

```swift
GroupBox {
    VStack(alignment: .leading, spacing: 12) {
        Label("CPU", systemImage: "cpu")
            .font(.headline)
        UsageBar(label: "Average", percent: cpu.average)
    }
}
```

`GroupBox` is a macOS-style card container with a subtle background. `Label` combines an icon and text. `systemImage` uses [SF Symbols](https://developer.apple.com/sf-symbols/) — Apple's built-in icon library.

### @State vs @Environment

```swift
@State private var selectedDate = Date()        // Local to this view, mutable
@Environment(PingService.self) private var pingService  // Injected from parent, shared
@AppStorage("routerEnabled") private var routerEnabled = true  // Backed by UserDefaults
```

- **`@State`** — View-local mutable state. When it changes, the view re-renders. Only the view that owns it can change it.
- **`@Environment`** — Reads an `@Observable` object that was injected by a parent view with `.environment()`.
- **`@AppStorage`** — Like `@State` but automatically synced to `UserDefaults` (persistent key-value storage).
- **`@Binding`** — A two-way reference to someone else's `@State` (used in `DayNavigationView`).

---

## 8. Charts: Visualizing Data

**File: `Views/LatencyChartView.swift`**

The app uses Apple's Swift Charts framework (macOS 14+).

### Basic Chart

```swift
Chart(buckets) { bucket in
    LineMark(
        x: .value("Time", bucket.timestamp),
        y: .value("Latency", bucket.avgLatency)
    )
    .foregroundStyle(by: .value("Connection", bucket.connection))
    .lineStyle(StrokeStyle(lineWidth: 1.5))
}
```

**Chart anatomy:**
- `Chart(data)` takes an array of `Identifiable` items.
- Inside the closure, you create **marks** for each data point.
- **`LineMark`** connects points with a line. Other marks: `BarMark`, `PointMark`, `AreaMark`, `RuleMark`, `RectangleMark`.
- `.value("Label", value)` maps data to axes.
- `.foregroundStyle(by: .value("Series", name))` creates separate colored series.

### Chart Modifiers

```swift
.chartXScale(domain: startOfDay(date)...endOfDay(date))  // Fix X axis to full day
.chartYScale(domain: 0...maxLatency)                       // Fix Y axis range
.chartForegroundStyleScale(domain: names, range: colors)   // Custom colors per series
.chartLegend(.hidden)                                      // Hide the legend
.chartXAxis {
    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
        AxisGridLine()
        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }
}
```

### Data Bucketing

Raw data (one point every 30 seconds) is too dense for a day-long chart. We aggregate into 5-minute buckets:

```swift
private var buckets: [ChartBucket] {
    let grouped = Dictionary(grouping: records) { record -> Date in
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.timestamp)
        let roundedMinute = (comps.minute! / 5) * 5
        return calendar.date(from: DateComponents(
            year: comps.year, month: comps.month, day: comps.day,
            hour: comps.hour, minute: roundedMinute
        ))!
    }
    return grouped.map { (timestamp, records) in
        // Average the values in each bucket
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        return ChartBucket(timestamp: timestamp, avgLatency: avg, ...)
    }.sorted { $0.timestamp < $1.timestamp }
}
```

`Dictionary(grouping:by:)` is a powerful Swift standard library function that groups array elements by a key.

### Chart Background Zones

The WiFi signal chart uses `chartBackground` to draw colored zones:

```swift
.chartBackground { proxy in
    GeometryReader { geo in
        let plotArea = proxy.plotSize
        Rectangle()
            .fill(.green.opacity(0.06))
            .frame(height: plotArea.height * (30.0 / 65.0))
        // Yellow and red zones below...
    }
}
```

`GeometryReader` gives you the actual pixel dimensions of a view — useful when you need to position things absolutely.

---

## 9. Environment: Dependency Injection

SwiftUI's environment system is how the app shares services across views without passing them through every initializer.

### Injecting (parent)

```swift
// In WiFiMonitorApp.swift
ContentView()
    .environment(pingService)
    .environment(pingStore)
```

### Reading (child, grandchild, any descendant)

```swift
// In any descendant view
@Environment(PingService.self) private var pingService
```

This is type-based — SwiftUI matches by the type (`PingService`). Every view in the hierarchy can read it without it being passed explicitly. This is the SwiftUI equivalent of dependency injection.

**Why not just use globals?** Environment values are scoped to the view hierarchy. The Settings window gets `RouterService` but not `WiFiService` because it doesn't need it. This makes dependencies explicit.

---

## 10. Settings and UserDefaults

**File: `Views/SettingsView.swift`**

### @AppStorage

```swift
@AppStorage("routerEnabled") private var routerEnabled = true
@AppStorage("routerIP") private var routerIP = "192.168.50.1"
```

`@AppStorage` is a SwiftUI property wrapper that reads/writes `UserDefaults` and triggers view updates. The string is the key, the value after `=` is the default if the key doesn't exist yet.

Under the hood, `UserDefaults` stores a `.plist` file at `~/Library/Preferences/com.local.WiFiMonitor.plist`.

### Settings Scene

```swift
// In WiFiMonitorApp.swift
Settings {
    SettingsView()
}
```

This creates a macOS Preferences window accessible via Cmd+, or the app menu. It's a built-in SwiftUI `Scene` type.

### SecureField

```swift
SecureField("Password", text: $routerPassword)
```

Like `TextField` but shows dots instead of characters. The `$` creates a `Binding` — a two-way connection between the text field and the property.

---

## 11. Networking: URLSession

**File: `Services/RouterService.swift`**

The router service makes HTTP requests using `URLSession`, Apple's networking API.

### Session Configuration

```swift
init() {
    let config = URLSessionConfiguration.ephemeral  // No disk caching
    config.timeoutIntervalForRequest = 10
    session = URLSession(configuration: config)
}
```

`ephemeral` means no cookies or cache are persisted to disk.

### Making a Request

```swift
private func authenticate(host: String, username: String, password: String) async throws -> String? {
    guard let url = URL(string: "http://\(cleanHost)/login.cgi") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
    request.httpBody = "login_authorization=\(credentials)".data(using: .utf8)

    let (data, _) = try await session.data(for: request)
    // Parse response...
}
```

**`async/await`** — Swift's modern concurrency. `await` pauses the function until the network request completes, without blocking the thread. The `async` keyword in the function signature means callers must use `await`.

**`throws`** — The function can fail. Callers must handle errors with `try`, `try?`, or `do/catch`.

### Calling Async from SwiftUI

```swift
Task { @MainActor in
    let error = await routerService.testConnection(...)
    isTesting = false    // Safe to update @State because we're on @MainActor
}
```

`Task` creates a new async context. `@MainActor` ensures the closure runs on the main thread (required for UI updates).

---

## 12. Shelling Out: Process

**File: `Services/PingService.swift`**

The app runs command-line tools (`ping`, `curl`) using Foundation's `Process` class.

### Running a Command

```swift
static func executePing(host: String) -> PingResult {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/sbin/ping")
    process.arguments = ["-c", "1", "-W", "3000", host]  // 1 packet, 3s timeout
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return PingResult(success: false, latency: nil)
    }

    guard process.terminationStatus == 0 else {
        return PingResult(success: false, latency: nil)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        return PingResult(success: false, latency: nil)
    }

    // Parse "time=XX.X" from output
    if let range = output.range(of: #"time=(\d+\.?\d*)"#, options: .regularExpression) {
        let match = output[range]
        let numberStr = match.replacingOccurrences(of: "time=", with: "")
        if let latency = Double(numberStr) {
            return PingResult(success: true, latency: latency)
        }
    }
    return PingResult(success: false, latency: nil)
}
```

**Step by step:**
1. Create a `Process` and a `Pipe` to capture output.
2. Set the executable path and arguments.
3. Run it and wait for it to finish.
4. Check the exit code (0 = success).
5. Read the output and parse with regex.

**Why shell out to `ping`?** Raw ICMP sockets require root privileges. The `/sbin/ping` binary is setuid, so it can send ICMP packets without our app needing root.

### Regex in Swift

```swift
output.range(of: #"time=(\d+\.?\d*)"#, options: .regularExpression)
```

`#"..."#` is a raw string literal — backslashes aren't escape characters, so regex is easier to write.

---

## 13. CoreWLAN: Reading WiFi Info

**File: `Services/WiFiService.swift`**

CoreWLAN is Apple's framework for interacting with WiFi hardware.

```swift
import CoreWLAN

private func sample() {
    guard let iface = CWWiFiClient.shared().interface() else { return }

    let rssi = iface.rssiValue()              // Signal strength in dBm (-30 to -90)
    guard rssi != 0 else { return }            // 0 = invalid reading
    let noise = iface.noiseMeasurement()       // Noise floor in dBm
    let txRate = iface.transmitRate()           // TX speed in Mbps
    let channel = iface.wlanChannel()?.channelNumber ?? 0
    let bandRaw = iface.wlanChannel()?.channelBand ?? .bandUnknown
}
```

**What the values mean:**
- **RSSI** (Received Signal Strength Indicator) — How strong the WiFi signal is. -30 is very strong (you're next to the router), -80 is very weak.
- **Noise** — Background electromagnetic noise. Typically -85 to -95 dBm.
- **SNR** (Signal-to-Noise Ratio) — `RSSI - Noise`. Higher is better. 25+ dB is good.
- **TX Rate** — How fast data can be sent. Depends on signal quality, channel width, and WiFi standard.

CoreWLAN reads are instant (no network I/O), so they run on the main thread.

---

## 14. How It All Fits Together

Here's the data flow from startup to pixels on screen:

### Startup

1. `WiFiMonitorApp` creates all 6 service/store objects.
2. They're injected into the view hierarchy via `.environment()`.
3. `ContentView.onAppear` starts `PingService`, `WiFiService`, and (optionally) `RouterService`.

### Every 30 Seconds (Ping + WiFi)

1. **PingService** timer fires.
2. Spawns a background thread → runs `/sbin/ping -c 1 1.1.1.1`.
3. Parses the output for `time=XX.X ms`.
4. Back on main thread: updates `lastLatency`, `lastSuccess`.
5. Creates a `PingRecord` and passes it to `PingStore.add()`.
6. PingStore appends to its in-memory array and writes to `2026-04-03.json`.
7. Because `PingService` is `@Observable`, any view reading `lastLatency` re-renders.

Simultaneously:

1. **WiFiService** timer fires.
2. Reads `CWWiFiClient.shared().interface()` for RSSI, noise, TX rate.
3. Creates a `WiFiSnapshot` and passes it to `WiFiStore.add()`.
4. WiFiStore writes to `wifi/wifi-2026-04-03.json` and increments `updateCount`.
5. `WiFiSignalChartView` sees `updateCount` change → re-reads snapshots → re-renders chart.

### Every 60 Seconds (Router)

1. **RouterService** timer fires → `poll()`.
2. If no auth token, calls `authenticate()` (HTTP POST to router's `/login.cgi`).
3. Makes 4 HTTP requests to `/appGet.cgi` (one per hook: wanlink, cpu, memory, netdev).
4. Parses responses (mix of JavaScript function-return format and JSON).
5. Computes CPU % from deltas, bandwidth from byte counter deltas.
6. Updates `@Observable` properties → views re-render.
7. Appends snapshot to history array and persists via `RouterStore`.

### View Rendering

SwiftUI is **declarative** and **reactive**:
- Views describe what they want to show based on current state.
- When an `@Observable` property changes, SwiftUI automatically figures out which views need to update.
- You never manually tell a view to refresh — it just happens.

The render cycle: `@Observable property changes` → `SwiftUI detects it` → `body is re-evaluated` → `SwiftUI diffs the old and new view trees` → `only the changed parts are redrawn`.

### Day Navigation

When you click the previous/next day buttons:
1. `selectedDate` (`@State`) changes.
2. `LatencyChartView`, `WiFiSignalChartView`, and `StatusBarView` all receive the new date.
3. Each view re-queries its store for that date's data.
4. Charts re-render with the historical data.

---

## Glossary

| Term | Meaning |
|------|---------|
| `@main` | Marks the app's entry point |
| `@Observable` | Makes a class's properties trigger SwiftUI updates when changed |
| `@State` | View-local mutable state that triggers re-renders |
| `@Environment` | Reads a value injected by a parent view |
| `@AppStorage` | `@State` backed by `UserDefaults` (persists across launches) |
| `@Binding` | Two-way reference to another view's `@State` |
| `some View` | "Returns a View, but I won't spell out the exact type" |
| `async/await` | Modern Swift concurrency — non-blocking asynchronous code |
| `try?` | "Try this, return nil if it fails" (ignores the error) |
| `guard` | Early return if a condition isn't met |
| `[weak self]` | Prevents retain cycles in closures |
| `Codable` | Protocol for automatic JSON encoding/decoding |
| `Identifiable` | Protocol requiring an `id` property (used by SwiftUI lists/charts) |
| SPM | Swift Package Manager — Swift's built-in build system and dependency manager |
| SF Symbols | Apple's built-in icon library (used with `systemImage:`) |
