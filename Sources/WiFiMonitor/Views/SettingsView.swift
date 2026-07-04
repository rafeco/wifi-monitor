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
        .onAppear { selectCurrentNetwork() }
        // The SSID may not be known yet when Settings first opens; select it
        // once it arrives.
        .onChange(of: wifiService.currentSSID) { _, _ in selectCurrentNetwork() }
        .onDisappear {
            // Apply any profile changes immediately.
            routerService.stop()
            routerService.start(store: routerStore, profiles: profileStore)
        }
    }

    private func selectCurrentNetwork() {
        if let ssid = wifiService.currentSSID {
            profileStore.discover(ssid: ssid)
            if selectedSSID == nil { selectedSSID = ssid }
        } else if selectedSSID == nil {
            selectedSSID = profileStore.profiles.first?.ssid
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
    @State private var compatibility: RouterCompatibility = .unknown
    @State private var isProbing = false
    @State private var detectedGateway: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showForgetConfirm = false

    /// The IP that will actually be used. The live gateway is only meaningful
    /// for the network we're currently on, and is cached to avoid re-shelling
    /// out to `route` on every render.
    private var effectiveIP: String {
        guard autoDetectIP else { return routerIP }
        if isCurrent, let detectedGateway { return detectedGateway }
        return routerIP
    }

    var body: some View {
        Form {
            Section {
                compatibilityHeader
            } header: {
                Text(profile.ssid)
            } footer: {
                if isCurrent {
                    Text("You're connected to this network.")
                }
            }

            if compatibility == .supported && routerEnabled {
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
                if compatibility == .supported {
                    Button("Save", action: save)
                }
                Button("Forget Network", role: .destructive) { showForgetConfirm = true }
            }
        }
        .formStyle(.grouped)
        .task {
            loadFromStore()
            if isCurrent && compatibility == .unknown { probe() }
        }
        .confirmationDialog("Forget \(profile.ssid)?", isPresented: $showForgetConfirm) {
            Button("Forget Network", role: .destructive) {
                profileStore.remove(ssid: profile.ssid)
            }
        } message: {
            Text("This removes the saved router settings and password for this network.")
        }
    }

    /// The first section's content depends on whether we've determined the
    /// router is supported.
    @ViewBuilder
    private var compatibilityHeader: some View {
        switch compatibility {
        case .supported:
            Toggle("Monitor this network's router", isOn: $routerEnabled)
        case .unsupported:
            Label("Unsupported router", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Only ASUS routers running ASUSWRT are supported, and this network's router doesn't appear to be one. Ping, WiFi signal, and the feels-like indicator still work.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unknown:
            if isProbing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking whether this network's router is supported…")
                        .foregroundStyle(.secondary)
                }
            } else if isCurrent {
                Text("This network's router hasn't been checked yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check router compatibility") { probe() }
            } else {
                Text("Connect to this network to check whether its router is supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadFromStore() {
        routerEnabled = profile.routerEnabled
        autoDetectIP = profile.autoDetectIP
        routerIP = profile.routerIP
        username = profile.username
        compatibility = profile.compatibility
        password = profileStore.password(for: profile.ssid) ?? ""
        detectedGateway = isCurrent ? RouterService.defaultGateway() : nil
    }

    private func save() {
        var updated = profile
        updated.routerEnabled = routerEnabled
        updated.autoDetectIP = autoDetectIP
        updated.routerIP = routerIP
        updated.username = username
        updated.compatibility = compatibility
        profileStore.upsert(updated)
        profileStore.setPassword(password, for: profile.ssid)
    }

    private func probe() {
        guard isCurrent else { return }
        isProbing = true
        testResult = nil
        Task { @MainActor in
            let result = await RouterService.probeCompatibility(host: effectiveIP)
            compatibility = result
            isProbing = false
            save()
        }
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
