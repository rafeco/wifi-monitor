import Foundation
import Network

/// The route to the same IPv4 destination used by PingService. A connected
/// adapter alone doesn't tell us which interface macOS will send traffic over.
struct ActiveConnection: Equatable {
    enum Transport {
        case ethernet, wifi, other, unknown, disconnected
    }

    var transport: Transport
    var interfaceName: String?

    static let unknown = ActiveConnection(transport: .unknown)

    var label: String {
        switch transport {
        case .ethernet: return "Using Ethernet"
        case .wifi: return "Using Wi-Fi"
        case .other: return "Using \(interfaceName ?? "another interface")"
        case .unknown: return "Active interface unknown"
        case .disconnected: return "No active connection"
        }
    }

    var symbol: String {
        switch transport {
        case .ethernet: return "cable.connector"
        case .wifi: return "wifi"
        case .disconnected: return "network.slash"
        case .other, .unknown: return "network"
        }
    }

    var wifiIsInactive: Bool {
        transport == .ethernet || transport == .other
    }

    static func interfaceName(fromRoute output: String) -> String? {
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2,
                  fields[0].trimmingCharacters(in: .whitespaces) == "interface" else { continue }
            let name = fields[1].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        return nil
    }

    static func resolve(routeInterface: String?, interfaces: [String: Transport], pathSatisfied: Bool) -> ActiveConnection {
        guard pathSatisfied else { return ActiveConnection(transport: .disconnected) }
        guard let routeInterface else {
            return .unknown
        }
        // Never guess Ethernet from an en* name: Wi-Fi also uses that prefix.
        // Tunnel routes remain explicit rather than implying a physical link.
        return ActiveConnection(transport: interfaces[routeInterface] ?? .other, interfaceName: routeInterface)
    }
}

@MainActor
@Observable
final class ActiveConnectionService {
    private(set) var connection: ActiveConnection = .unknown

    private var monitor: NWPathMonitor?
    private var timer: Timer?
    private var requestID = 0

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self, weak monitor] path in
            Task { @MainActor in
                guard let self, let monitor, self.monitor === monitor else { return }
                self.refresh(path: path)
            }
        }
        monitor.start(queue: DispatchQueue(label: "WiFiMonitor.activeConnection"))
        // Also catch routing changes that don't change path availability.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let monitor = self.monitor else { return }
                self.refresh(path: monitor.currentPath)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        timer?.invalidate()
        timer = nil
        requestID += 1
        connection = .unknown
    }

    private func refresh(path: NWPath) {
        guard monitor != nil else { return }
        requestID += 1
        let request = requestID
        let interfaces = Dictionary(path.availableInterfaces.map { interface in
            let transport: ActiveConnection.Transport
            switch interface.type {
            case .wiredEthernet: transport = .ethernet
            case .wifi: transport = .wifi
            default: transport = .other
            }
            return (interface.name, transport)
        }, uniquingKeysWith: { first, _ in first })
        let satisfied = path.status == .satisfied
        Task { [weak self] in
            let routeInterface = await Task.detached(priority: .utility) {
                Self.readRouteInterface()
            }.value
            guard let self, self.monitor != nil, request == self.requestID else { return }
            self.connection = ActiveConnection.resolve(
                routeInterface: routeInterface, interfaces: interfaces, pathSatisfied: satisfied
            )
        }
    }

    nonisolated static func readRouteInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "1.1.1.1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else { return nil }
            return ActiveConnection.interfaceName(fromRoute: output)
        } catch {
            return nil
        }
    }
}
