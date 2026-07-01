import SwiftUI

struct SettingsView: View {
    @AppStorage("routerEnabled") private var routerEnabled = true
    @AppStorage("routerIP") private var routerIP = "192.168.50.1"
    @AppStorage("routerAutoDetectIP") private var autoDetectIP = true
    @AppStorage("routerUsername") private var routerUsername = "admin"
    @AppStorage("routerPassword") private var routerPassword = ""
    @AppStorage("routerHomeSSID") private var homeSSID = ""
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @State private var testResult: String?
    @State private var isTesting = false

    /// The IP that will actually be used, so the user can see what auto-detect resolved to.
    private var effectiveIP: String {
        autoDetectIP ? (RouterService.defaultGateway() ?? routerIP) : routerIP
    }

    var body: some View {
        Form {
            Section("Router") {
                Toggle("Enable router monitoring", isOn: $routerEnabled)
            }

            Section("Router Connection") {
                Toggle("Detect router IP from current network", isOn: $autoDetectIP)

                if autoDetectIP {
                    LabeledContent("Router IP", value: effectiveIP)
                } else {
                    TextField("Router IP", text: $routerIP)
                }

                TextField("Username", text: $routerUsername)
                SecureField("Password", text: $routerPassword)

                if !homeSSID.isEmpty {
                    LabeledContent("Home network", value: homeSSID)
                }

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
        Task { @MainActor in
            let error = await routerService.testConnection(
                host: effectiveIP, username: routerUsername, password: routerPassword
            )
            isTesting = false
            testResult = error == nil ? "Success — connected to router" : "Failed: \(error!)"
        }
    }
}
