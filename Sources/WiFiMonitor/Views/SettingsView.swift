import SwiftUI

struct SettingsView: View {
    @Environment(NetworkProfileStore.self) private var profileStore
    @Environment(WiFiService.self) private var wifiService
    @Environment(RouterService.self) private var routerService
    @Environment(RouterStore.self) private var routerStore
    @State private var selectedSSID: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSSID) {
                Section("Networks") {
                    ForEach(profileStore.profiles) { profile in
                        NetworkRow(profile: profile, isCurrent: profile.ssid == wifiService.currentSSID)
                            .tag(profile.ssid)
                    }
                }
                if profileStore.profiles.isEmpty {
                    Text("No networks yet. Join a WiFi network to see it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 200)
        } detail: {
            if let ssid = selectedSSID, let profile = profileStore.profile(for: ssid) {
                NetworkDetailView(profile: profile, isCurrent: ssid == wifiService.currentSSID)
                    .id(ssid)  // reset editing state when switching networks
            } else {
                Text("Select a network")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 660, height: 460)
        .onAppear {
            if let ssid = wifiService.currentSSID {
                profileStore.discover(ssid: ssid)
                if selectedSSID == nil { selectedSSID = ssid }
            } else if selectedSSID == nil {
                selectedSSID = profileStore.profiles.first?.ssid
            }
        }
        .onDisappear {
            // Apply any profile changes immediately.
            routerService.stop()
            routerService.start(store: routerStore, profiles: profileStore)
        }
    }
}

/// Sidebar row: network name, a "connected" badge, and a monitored indicator.
private struct NetworkRow: View {
    let profile: NetworkProfile
    let isCurrent: Bool

    var body: some View {
        HStack {
            Image(systemName: profile.routerEnabled ? "dot.radiowaves.left.and.right" : "wifi")
                .foregroundStyle(profile.routerEnabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.ssid)
                if isCurrent {
                    Text("Connected")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}

/// Per-network router configuration form.
private struct NetworkDetailView: View {
    let profile: NetworkProfile
    let isCurrent: Bool

    @Environment(NetworkProfileStore.self) private var profileStore
    @Environment(RouterService.self) private var routerService

    @State private var routerEnabled = false
    @State private var autoDetectIP = true
    @State private var routerIP = "192.168.50.1"
    @State private var username = "admin"
    @State private var password = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showForgetConfirm = false

    /// The IP that will actually be used. The live gateway is only meaningful
    /// for the network we're currently on.
    private var effectiveIP: String {
        guard autoDetectIP else { return routerIP }
        if isCurrent { return RouterService.defaultGateway() ?? routerIP }
        return routerIP
    }

    var body: some View {
        Form {
            Section {
                Toggle("Monitor this network's router", isOn: $routerEnabled)
            } header: {
                Text(profile.ssid)
            } footer: {
                if isCurrent {
                    Text("You're connected to this network.")
                }
            }

            if routerEnabled {
                Section("Router Connection") {
                    Toggle("Detect router IP from current network", isOn: $autoDetectIP)

                    if autoDetectIP {
                        LabeledContent("Router IP", value: isCurrent ? effectiveIP : "Auto-detected on connect")
                    } else {
                        TextField("Router IP", text: $routerIP)
                    }

                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)

                    HStack {
                        Button("Test Connection") { testConnection() }
                            .disabled(password.isEmpty || isTesting || !isCurrent)

                        if isTesting {
                            ProgressView().controlSize(.small)
                        }
                        if let testResult {
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(testResult.contains("Success") ? .green : .red)
                        }
                    }
                    if !isCurrent {
                        Text("Connect to this network to test.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Save", action: save)
                Button("Forget Network", role: .destructive) { showForgetConfirm = true }
            }
        }
        .formStyle(.grouped)
        .task { loadFromStore() }
        .confirmationDialog("Forget \(profile.ssid)?", isPresented: $showForgetConfirm) {
            Button("Forget Network", role: .destructive) {
                profileStore.remove(ssid: profile.ssid)
            }
        } message: {
            Text("This removes the saved router settings and password for this network.")
        }
    }

    private func loadFromStore() {
        routerEnabled = profile.routerEnabled
        autoDetectIP = profile.autoDetectIP
        routerIP = profile.routerIP
        username = profile.username
        password = profileStore.password(for: profile.ssid) ?? ""
    }

    private func save() {
        var updated = profile
        updated.routerEnabled = routerEnabled
        updated.autoDetectIP = autoDetectIP
        updated.routerIP = routerIP
        updated.username = username
        profileStore.upsert(updated)
        profileStore.setPassword(password, for: profile.ssid)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task { @MainActor in
            let error = await routerService.testConnection(
                host: effectiveIP, username: username, password: password
            )
            isTesting = false
            testResult = error == nil ? "Success — connected to router" : "Failed: \(error!)"
        }
    }
}
