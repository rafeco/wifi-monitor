import SwiftUI

struct SettingsView: View {
    @AppStorage("routerEnabled") private var routerEnabled = true
    @AppStorage("routerIP") private var routerIP = "192.168.50.1"
    @AppStorage("routerPassword") private var routerPassword = ""
    @AppStorage("routerUsername") private var routerUsername = "admin"
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Router") {
                Toggle("Enable router monitoring", isOn: $routerEnabled)
            }

            Section("Router Connection") {
                TextField("Router IP", text: $routerIP)
                TextField("Username", text: $routerUsername)
                SecureField("Password", text: $routerPassword)

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(routerPassword.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.contains("Success") ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
        .onDisappear {
            routerService.stop()
            if routerEnabled {
                routerService.start(store: routerStore)
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            let success = await routerService.testConnection(
                host: routerIP, username: routerUsername, password: routerPassword
            )
            isTesting = false
            testResult = success ? "Success — connected to router" : "Failed — check IP and credentials"
        }
    }
}
