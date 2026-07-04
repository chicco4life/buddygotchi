import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    let engine: BuddyEngine
    let esp32Output: ESP32Output

    @AppStorage(DefaultsKey.interactiveMode) private var interactiveMode = false
    @AppStorage(DefaultsKey.buddySpecies) private var species = "cat"
    @AppStorage(DefaultsKey.setupCompleted) private var setupCompleted = false
    @AppStorage(DefaultsKey.approvalMode) private var approvalMode = false
    @AppStorage(DefaultsKey.esp32PeripheralUUID) private var esp32UUID: String?
    @State private var launchAtLogin = false
    @State private var launchAtLoginStatus = LoginItemManager.Status.disabled
    @State private var agentInstalled: [AgentKind: Bool] = [:]

    @State private var scanner = BLEScanner()
    @State private var selectedDeviceUUID: UUID?
    @State private var showingFirmwareUpdate = false
    @State private var showingRemoveConfirmation = false
    @State private var showingUpdaterUnavailable = false
    @State private var uninstallError: String?

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
            refreshLoginItemState()
            for agent in AgentKind.allCases {
                agentInstalled[agent] = HookInstaller.shared.isInstalled(agent: agent)
            }
            // If an update is mid-flight (popover was closed mid-upload), bring
            // the sheet back so the user can watch progress.
            if esp32Output.firmwareUpdater.state.isMidFlight {
                showingFirmwareUpdate = true
            }
        }
        .onDisappear {
            scanner.stop()
        }
        .sheet(isPresented: $showingFirmwareUpdate) {
            FirmwareUpdateView(
                updater: esp32Output.firmwareUpdater,
                isPresented: $showingFirmwareUpdate
            )
        }
        .alert("Remove Buddygotchi?", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove and quit", role: .destructive) {
                removeBuddygotchi()
            }
        } message: {
            Text("This removes Buddygotchi hook entries from Claude Code, Cursor, and Codex, deletes ~/.buddygotchi, unregisters launch at login, clears notifications, and quits. Your app stays wherever you put it.")
        }
        .alert("Updates unavailable", isPresented: $showingUpdaterUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Automatic updates are available in the packaged app when Sparkle.framework is bundled.")
        }
        .alert("Could not remove Buddygotchi", isPresented: Binding(
            get: { uninstallError != nil },
            set: { if !$0 { uninstallError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uninstallError ?? "Unknown error")
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
                    refreshLoginItemState()
                }

                Divider().padding(.horizontal, 12)

                if launchAtLoginStatus == .requiresApproval {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(BuddyTheme.accent)
                        Text("Approve Buddygotchi in System Settings, Login Items.")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider().padding(.horizontal, 12)
                }

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

                if esp32UUID != nil {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hardware buddy").font(.system(.callout, design: .rounded))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(esp32Output.connectionState == .connected ? BuddyTheme.accent : Color.secondary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(esp32Output.connectionState.rawValue)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Unpair") {
                            esp32Output.unpair()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if esp32Output.connectionState == .connected {
                        Divider().padding(.horizontal, 12)
                        firmwareRow
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hardware buddy").font(.system(.callout, design: .rounded))
                            Text("Not paired")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(scanner.isScanning ? "Scanning..." : "Pair Device") {
                            if scanner.isScanning { scanner.stop() }
                            else { scanner.start() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(BuddyTheme.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().padding(.horizontal, 12)

                    Link(destination: AppMetadata.flashURL) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bare hardware buddy").font(.system(.callout, design: .rounded))
                                Text("Flash it first in Chrome or Edge.")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(BuddyPlainButtonStyle())
                }
            }
            .buddyGroupedCard()

            if scanner.isScanning && !scanner.devices.isEmpty {
                ForEach(scanner.devices, id: \.identifier) { device in
                    Button {
                        UserDefaults.standard.set(device.identifier.uuidString, forKey: esp32PeripheralUUIDKey)
                        selectedDeviceUUID = device.identifier
                        scanner.stop()
                        esp32Output.connectToSavedDevice()
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

    // MARK: - Firmware row

    private var firmwareRow: some View {
        Button {
            showingFirmwareUpdate = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Firmware").font(.system(.callout, design: .rounded))
                    Text(esp32Output.firmwareUpdater.deviceVersion ?? "Unknown")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                firmwareTrailingLabel
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(BuddyPlainButtonStyle())
        .accessibilityLabel(firmwareAccessibilityLabel)
    }

    @ViewBuilder
    private var firmwareTrailingLabel: some View {
        switch esp32Output.firmwareUpdater.state {
        case .available(let release, _):
            HStack(spacing: 4) {
                Circle().fill(BuddyTheme.accent).frame(width: 6, height: 6)
                Text("Update · \(release.version)")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(BuddyTheme.accent)
            }
        case .upToDate:
            Text("Up to date")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        case .downloading(let p), .uploading(let p, _):
            Text("\(Int(p * 100))%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(BuddyTheme.accent)
        case .verifying, .rebooting:
            Text("Updating…")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(BuddyTheme.accent)
        case .success:
            Text("Updated")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(BuddyTheme.celebrateGreen)
        case .failed:
            Text("Failed")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(BuddyTheme.destructive)
        case .checking, .idle:
            Text("Checking…")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private var firmwareAccessibilityLabel: String {
        let v = esp32Output.firmwareUpdater.deviceVersion ?? "unknown"
        switch esp32Output.firmwareUpdater.state {
        case .available(let r, _): return "Firmware \(v), update available to \(r.version)"
        case .upToDate:            return "Firmware \(v), up to date"
        case .downloading, .uploading, .verifying, .rebooting:
                                   return "Firmware update in progress"
        case .success:             return "Firmware updated"
        case .failed:              return "Firmware update failed"
        case .checking, .idle:     return "Checking for firmware updates"
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
                    Text(AppMetadata.displayVersion)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)

                Divider().padding(.horizontal, 12)

                Button {
                    if SparkleUpdateManager.shared.isAvailable {
                        SparkleUpdateManager.shared.checkForUpdates()
                    } else {
                        showingUpdaterUnavailable = true
                    }
                } label: {
                    HStack {
                        Text("Check for updates")
                            .font(.system(.callout, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BuddyPlainButtonStyle())

                Divider().padding(.horizontal, 12)

                Link(destination: AppMetadata.supportURL) {
                    HStack {
                        Text("Help and support")
                            .font(.system(.callout, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(BuddyPlainButtonStyle())

                Divider().padding(.horizontal, 12)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                    Text("Update checks read a static appcast. No analytics or device identifiers are sent.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
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

            Button("Remove Buddygotchi…") {
                showingRemoveConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(BuddyTheme.destructive)
        }
    }

    // MARK: - Helpers

    private func cycleSpecies(_ direction: Int) {
        guard let idx = buddyOrder.firstIndex(of: species) else { return }
        let next = (idx + direction + buddyOrder.count) % buddyOrder.count
        species = buddyOrder[next]
        esp32Output.sendNow()
    }

    private func refreshLoginItemState() {
        launchAtLoginStatus = LoginItemManager.shared.status
        launchAtLogin = launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    private func removeBuddygotchi() {
        do {
            try ConsumerUninstaller.removeInstalledState()
            NSApplication.shared.terminate(nil)
        } catch {
            uninstallError = error.localizedDescription
        }
    }

    private var currentSpeciesIndex: Int {
        buddyOrder.firstIndex(of: species) ?? 0
    }

    private var currentSpeciesColor: Color {
        buddySpeciesColor(for: species)
    }
}
