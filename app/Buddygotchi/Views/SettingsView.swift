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

    @State private var scanner = BLEScanner()
    @State private var selectedDeviceUUID: UUID?

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
                .buttonStyle(BuddyPlainButtonStyle())
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
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.popoverHeight)
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLogin = LoginItemManager.shared.isEnabled
            for agent in AgentKind.allCases {
                agentInstalled[agent] = HookInstaller.shared.isInstalled(agent: agent)
            }
        }
        .onDisappear {
            scanner.stop()
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuddySectionHeader("General")

            VStack(spacing: 0) {
                BuddySettingToggle(
                    title: "Launch at Login",
                    description: "Start Buddygotchi when you log in to your Mac.",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.shared.setEnabled(newValue)
                    launchAtLogin = LoginItemManager.shared.isEnabled
                }

                Divider().padding(.horizontal, 12)

                BuddySettingToggle(
                    title: "Interactive Mode",
                    description: "Auto-show when your buddy celebrates or needs attention.",
                    isOn: $interactiveMode
                )

                Divider().padding(.horizontal, 12)

                BuddySettingToggle(
                    title: "Local Approval Mode",
                    description: "Route tool approvals through Buddygotchi instead of your agent's built-in dialog.",
                    isOn: $approvalMode
                )
                .onChange(of: approvalMode) { _, newValue in
                    BuddyConfig.setApprovalMode(newValue)
                    if !newValue {
                        engine.resolveAllPendingApprovals(decision: .allow)
                    }
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
                .buttonStyle(BuddyPlainButtonStyle())
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
                .buttonStyle(BuddyPlainButtonStyle())
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
                    Button(scanner.isScanning ? "Scanning..." : "Scan") {
                        if scanner.isScanning { scanner.stop() }
                        else { scanner.start() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(BuddyTheme.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buddyGroupedCard()

            if scanner.isScanning && !scanner.devices.isEmpty {
                ForEach(scanner.devices, id: \.identifier) { device in
                    Button {
                        UserDefaults.standard.set(device.identifier.uuidString, forKey: "esp32PeripheralUUID")
                        selectedDeviceUUID = device.identifier
                        scanner.stop()
                    } label: {
                        HStack {
                            Text(device.name).font(.system(.caption, design: .rounded))
                            Spacer()
                            Text("Connect")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(BuddyTheme.accent)
                        }
                    }
                    .buttonStyle(BuddyPlainButtonStyle())
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
}
