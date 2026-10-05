import Foundation

@main
struct ActiveConnectionTests {
    @MainActor
    static func main() async throws {
        let adapters: [String: ActiveConnection.Transport] = ["en0": .wifi, "en7": .ethernet]
        let wired = ActiveConnection.resolve(routeInterface: "en7", interfaces: adapters, pathSatisfied: true)
        precondition(wired.transport == .ethernet && wired.wifiIsInactive)
        precondition(wired.label == "Using Ethernet")
        let wifi = ActiveConnection.resolve(routeInterface: "en0", interfaces: adapters, pathSatisfied: true)
        precondition(wifi.transport == .wifi && !wifi.wifiIsInactive)
        let tunnel = ActiveConnection.resolve(routeInterface: "utun4", interfaces: adapters, pathSatisfied: true)
        precondition(tunnel.transport == .other && tunnel.label == "Using utun4")
        precondition(ActiveConnection.resolve(routeInterface: "en9", interfaces: adapters, pathSatisfied: true).transport == .other)
        precondition(ActiveConnection.resolve(routeInterface: nil, interfaces: adapters, pathSatisfied: true) == .unknown)
        precondition(ActiveConnection.resolve(routeInterface: nil, interfaces: adapters, pathSatisfied: false).transport == .disconnected)
        precondition(ActiveConnection.resolve(routeInterface: "en7", interfaces: adapters, pathSatisfied: false).transport == .disconnected)
        precondition(ActiveConnection.interfaceName(fromRoute: "gateway: 192.168.1.1\n  interface: en7\n flags: <UP>") == "en7")
        precondition(ActiveConnection.interfaceName(fromRoute: "interface: \n") == nil)
        precondition(ActiveConnection.interfaceName(fromRoute: "route: socket: Operation not permitted") == nil)
        print("Active connection: route selection, fallback, and parsing checks passed")

        if CommandLine.arguments.contains("--live") {
            let service = ActiveConnectionService()
            service.start()
            try await Task.sleep(for: .seconds(2))
            let connection = service.connection
            print("Live route: \(connection.label) (\(connection.interfaceName ?? "none"))")
            precondition(connection.transport != .unknown, "Live route detection must resolve an interface")
            service.stop()
            precondition(service.connection == .unknown)
            service.start()
            try await Task.sleep(for: .seconds(2))
            precondition(service.connection.transport != .unknown, "Monitoring must restart after stop")
            service.stop()
            print("Live monitoring start/stop/restart checks passed")
        }
    }
}
