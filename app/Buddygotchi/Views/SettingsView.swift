import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    let engine: BuddyEngine

    @AppStorage("interactiveMode") private var interactiveMode = false
    @AppStorage("buddySpecies") private var species = "cat"
    @AppStorage("setupCompleted") private var setupCompleted = false
    @AppStorage("approvalMode") private var approvalMode = false
    @State private var launchAtLogin = false
    @State private var agentInstalled: [AgentKind: Bool] = [:]

    @State private var bleManager: BLEManager?
    @State private var discoveredDevices: [BLEManager.DiscoveredPeripheral] = []
    @State private var selectedDeviceUUID: UUID?
    @State private var bleScanTask: Task<Void, Never>?
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Settings")
                            .font(.system(.headline, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to live view")
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    generalSection
                    buddySection
                    agentsSection
                    displaysSection
                    aboutSection
                }
                .padding()
            }
        }
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.fullPanelHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLogin = LoginItemManager.shared.isEnabled
            for agent in AgentKind.allCases {
                agentInstalled[agent] = HookInstaller.shared.isInstalled(agent: agent)
            }
        }
        .onDisappear {
            stopBLEScan()
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuddySectionHeader("General")

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .tint(BuddyTheme.accent)
                        .onChange(of: launchAtLogin) { _, newValue in
                            LoginItemManager.shared.setEnabled(newValue)
                        }
                    Text("Start Buddygotchi when you log in to your Mac.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Interactive Mode", isOn: $interactiveMode)
                        .tint(BuddyTheme.accent)
                    Text("Auto-show when your buddy celebrates or needs attention.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Local Approval Mode", isOn: $approvalMode)
                        .tint(BuddyTheme.accent)
                        .onChange(of: approvalMode) { _, newValue in
                            BuddyConfig.setApprovalMode(newValue)
                            if !newValue {
                                engine.resolveAllPendingApprovals(decision: .allow)
                            }
                        }
                    Text("Route tool approvals through Buddygotchi instead of your agent's built-in dialog.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.horizontal, 12)

                HStack {
                    Text("HTTP Port")
                        .font(.system(.callout, design: .rounded))
                    Spacer()
                    Text("\(BuddyConfig.default.httpPort)")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            .buddyGroupedCard()
        }
    }

    // MARK: - Buddy

    private var buddySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BuddySectionHeader("Buddy")

            HStack(spacing: 12) {
                Button(action: { cycleSpecies(-1) }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous species")

                VStack(spacing: 8) {
                    PetStageView(petState: .idle, species: species)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(currentSpeciesColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(species)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(currentSpeciesColor)
                    }

                    Text("\(currentSpeciesIndex + 1) of \(buddyOrder.count)")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 140)

                Button(action: { cycleSpecies(1) }) {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next species")
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Species picker, \(species), \(currentSpeciesIndex + 1) of \(buddyOrder.count)")
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuddySectionHeader("Agents")

            VStack(spacing: 0) {
                ForEach(Array(AgentKind.allCases.enumerated()), id: \.element) { index, agent in
                    let installed = agentInstalled[agent] ?? false
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.displayName).font(.system(.callout, design: .rounded))
                            Text(installed ? "Installed" : "Not Installed")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(installed ? BuddyTheme.accent : .secondary)
                        }
                        Spacer()
                        if installed {
                            Button("Reinstall") {
                                HookInstaller.shared.uninstall(agent: agent)
                                if HookInstaller.shared.install(agent: agent) {
                                    agentInstalled[agent] = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(BuddyTheme.accent)
                        } else {
                            Button("Install") {
                                if HookInstaller.shared.install(agent: agent) {
                                    agentInstalled[agent] = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(BuddyTheme.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)

                    if index < AgentKind.allCases.count - 1 {
                        Divider().padding(.horizontal, 12)
                    }
                }
            }
            .buddyGroupedCard()
        }
    }

    // MARK: - Displays

    private var displaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuddySectionHeader("Displays")

            VStack(spacing: 0) {
                HStack {
                    Text("This Mac").font(.system(.callout, design: .rounded))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BuddyTheme.accent)
                        Text("Active")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(BuddyTheme.accent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("This Mac, active")

                Divider().padding(.horizontal, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("M5Stack").font(.system(.callout, design: .rounded))
                        Text(esp32Status)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isScanning ? "Scanning..." : "Scan") {
                        if isScanning { stopBLEScan() }
                        else { startBLEScan() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(BuddyTheme.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buddyGroupedCard()

            if isScanning && !discoveredDevices.isEmpty {
                ForEach(discoveredDevices, id: \.identifier) { device in
                    Button {
                        UserDefaults.standard.set(device.identifier.uuidString, forKey: "esp32PeripheralUUID")
                        selectedDeviceUUID = device.identifier
                        stopBLEScan()
                    } label: {
                        HStack {
                            Text(device.name).font(.system(.caption, design: .rounded))
                            Spacer()
                            Text("Connect")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(BuddyTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .buddyCard()
                    .accessibilityLabel("Connect to \(device.name)")
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuddySectionHeader("About")

            VStack(spacing: 0) {
                HStack {
                    Text("Version").font(.system(.callout, design: .rounded))
                    Spacer()
                    Text("v0.3.0")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            .buddyGroupedCard()

            HStack(spacing: 12) {
                Button("Reset Setup") {
                    setupCompleted = false
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(BuddyTheme.destructive)

                Spacer()

                Button("Quit Buddygotchi") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(BuddyTheme.destructive)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func cycleSpecies(_ direction: Int) {
        guard let idx = buddyOrder.firstIndex(of: species) else { return }
        let next = (idx + direction + buddyOrder.count) % buddyOrder.count
        species = buddyOrder[next]
    }

    private var currentSpeciesIndex: Int {
        buddyOrder.firstIndex(of: species) ?? 0
    }

    private var currentSpeciesColor: Color {
        buddySpeciesColor(for: species)
    }

    private var esp32Status: String {
        if let uuid = UserDefaults.standard.string(forKey: "esp32PeripheralUUID") {
            return "Paired: \(uuid.prefix(8))..."
        }
        return "Not connected"
    }

    // MARK: - BLE Scan

    private func startBLEScan() {
        stopBLEScan()
        isScanning = true
        let manager = BLEManager()
        bleManager = manager
        discoveredDevices = []
        let stream = manager.startScan()
        bleScanTask = Task {
            for await device in stream {
                if !discoveredDevices.contains(where: { $0.identifier == device.identifier }) {
                    discoveredDevices.append(device)
                }
            }
        }
    }

    private func stopBLEScan() {
        isScanning = false
        bleScanTask?.cancel()
        bleScanTask = nil
        bleManager?.stopScan()
        bleManager = nil
    }
}
