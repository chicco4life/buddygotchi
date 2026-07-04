import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let serverHealth: ServerHealth?
    var onOpenOnboarding: () -> Void = {}

    @AppStorage(DefaultsKey.interactiveMode) private var interactiveMode = false
    @AppStorage(DefaultsKey.soundsEnabled) private var soundsEnabled = true
    @AppStorage(DefaultsKey.buddySpecies) private var species = Pet.defaultSpecies
    @AppStorage(DefaultsKey.setupCompleted) private var setupCompleted = false
    @AppStorage(DefaultsKey.approvalMode) private var approvalMode = false
    @AppStorage(DefaultsKey.esp32PeripheralUUID) private var esp32UUID: String?
    @State private var launchAtLogin = false
    @State private var launchAtLoginStatus = LoginItemManager.Status.disabled
    @State private var agentHealth: [AgentKind: HookHealth] = [:]

    @State private var scanner = BLEScanner()
    @State private var selectedDeviceUUID: UUID?
    @State private var showingFirmwareUpdate = false
    @State private var showingUnpairConfirmation = false
    @State private var isExportingBugReport = false
    @State private var bugReportError: String?
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
                            .font(.buddy(15, weight: .semibold))
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
                .fill(BuddyTheme.textPrimary.opacity(0.06))
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
                agentHealth[agent] = HookInstaller.shared.verify(agent: agent)
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
        .alert("Couldn't export bug report", isPresented: bugReportErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bugReportError ?? "The report could not be written.")
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
                            .foregroundStyle(BuddyTheme.amber)
                        Text("Approve Buddygotchi in System Settings, Login Items.")
                            .font(.buddy(11))
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
                    title: "Sounds",
                    description: "Play a short sound for attention, errors, and long completions.",
                    isOn: $soundsEnabled
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
                        engine.resolveAllPendingApprovals(decision: .passthrough)
                    }
                }

                Divider().padding(.horizontal, 12)

                DisclosureGroup {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, 12)
                        HStack {
                            Text("HTTP Port")
                                .font(.buddy(13))
                            Spacer()
                            Text("\(BuddyConfig.default.httpPort)")
                                .font(.buddy(13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)

                        Divider().padding(.leading, 12)
                        serverHealthRow

                        Divider().padding(.leading, 12)
                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: BuddyConfig.default.stateDir))
                        } label: {
                            HStack {
                                Text("Open config folder")
                                    .font(.buddy(13))
                                Spacer()
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                    }
                } label: {
                    Text("Advanced")
                        .font(.buddy(13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
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
                            .font(.buddy(11, weight: .semibold))
                            .foregroundStyle(currentSpeciesColor)
                    }

                    Text("\(currentSpeciesIndex + 1) of \(buddyOrder.count)")
                        .font(.buddy(11))
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
                    let health = agentHealth[agent] ?? .notInstalled
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.displayName).font(.buddy(13))
                            Text(hookHealthLabel(health))
                                .font(.buddy(11))
                                .foregroundStyle(hookHealthColor(health))
                        }
                        Spacer()
                        if health == .installed {
                            Button("Repair") {
                                do {
                                    try HookInstaller.shared.repair(agent: agent)
                                    agentHealth[agent] = HookInstaller.shared.verify(agent: agent)
                                } catch {
                                    agentHealth[agent] = .corrupted(reason: error.localizedDescription)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(BuddyTheme.amber)
                        } else {
                            Button(health.repairable ? "Repair" : "Connect") {
                                do {
                                    if health.repairable {
                                        try HookInstaller.shared.repair(agent: agent)
                                    } else {
                                        try HookInstaller.shared.installOrThrow(agent: agent)
                                    }
                                    agentHealth[agent] = HookInstaller.shared.verify(agent: agent)
                                } catch {
                                    agentHealth[agent] = .corrupted(reason: error.localizedDescription)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(BuddyTheme.amber)
                            .disabled(!health.repairable && !canInstall(health))
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

    private func hookHealthLabel(_ health: HookHealth) -> String {
        switch health {
        case .installed:
            return "Connected"
        case .notInstalled:
            return "Not connected"
        case .outdated(let installed, let current):
            return "Needs repair - v\(installed) to v\(current)"
        case .corrupted(let reason):
            return "Needs repair - \(reason)"
        }
    }

    private func hookHealthColor(_ health: HookHealth) -> Color {
        switch health {
        case .installed:
            return BuddyTheme.amber
        case .outdated, .corrupted:
            return .orange
        case .notInstalled:
            return .secondary
        }
    }

    private func canInstall(_ health: HookHealth) -> Bool {
        if case .notInstalled = health { return true }
        return false
    }

    // MARK: - Displays

    private var displaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BuddySectionHeader("Displays")

            VStack(spacing: 0) {
                HStack {
                    Text("This Mac").font(.buddy(13))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BuddyTheme.amber)
                        Text("Active")
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.amber)
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
                            Text("Hardware buddy").font(.buddy(13))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(esp32Output.connectionState == .connected ? BuddyTheme.amber : Color.secondary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                Text(esp32Output.connectionState.rawValue)
                                    .font(.buddy(11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Forget") {
                            showingUnpairConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .confirmationDialog("Forget this buddy?", isPresented: $showingUnpairConfirmation) {
                        Button("Forget this buddy", role: .destructive) {
                            esp32Output.unpair()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your hardware buddy can be paired again later.")
                    }

                    if esp32Output.connectionState == .connected {
                        Divider().padding(.horizontal, 12)
                        firmwareRow
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hardware buddy").font(.buddy(13))
                            Text("Not paired")
                                .font(.buddy(11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(scanner.isScanning ? "Scanning…" : "Pair a buddy") {
                            if scanner.isScanning { scanner.stop() }
                            else { scanner.start() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(BuddyTheme.amber)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    Divider().padding(.horizontal, 12)

                    Link(destination: AppMetadata.flashURL) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bare hardware buddy").font(.buddy(13))
                                Text("Flash it first in Chrome or Edge.")
                                    .font(.buddy(11))
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
                            Text(device.name).font(.buddy(11))
                            Spacer()
                            Text("Connect")
                                .font(.buddy(11))
                                .foregroundStyle(BuddyTheme.amber)
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
                    Text("Firmware").font(.buddy(13))
                    Text(esp32Output.firmwareUpdater.deviceVersion ?? "Unknown")
                        .font(.buddy(11))
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
                Circle().fill(BuddyTheme.amber).frame(width: 6, height: 6)
                Text("Update · \(release.version)")
                    .font(.buddy(9.5, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amber)
            }
        case .upToDate:
            Text("Up to date")
                .font(.buddy(11))
                .foregroundStyle(.secondary)
        case .downloading(let p), .uploading(let p, _):
            Text("\(Int(p * 100))%")
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.amber)
        case .verifying, .rebooting:
            Text("Updating…")
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.amber)
        case .success:
            Text("Updated")
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.green)
        case .failed:
            Text("Failed")
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.stuckRed)
        case .checking, .idle:
            Text("Checking…")
                .font(.buddy(11))
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
                    Text("Version").font(.buddy(13))
                    Spacer()
                    Text(AppMetadata.displayVersion)
                        .font(.buddy(13))
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
                            .font(.buddy(13))
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
                            .font(.buddy(13))
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
                        .font(.buddy(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buddyGroupedCard()

            Button {
                Task { await exportBugReport() }
            } label: {
                HStack {
                    if isExportingBugReport {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "ladybug")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Export bug report")
                        .font(.buddy(13))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .buddyGroupedCard()
            .disabled(isExportingBugReport)

            Text("Buddygotchi keeps agent activity local to this Mac. Network access is limited to update checks and firmware downloads when those features are available.")
                .font(.buddy(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Run setup again") {
                    setupCompleted = false
                    isPresented = false
                    onOpenOnboarding()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(BuddyTheme.stuckRed)

                Spacer()

                Button("Quit Buddygotchi") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(BuddyTheme.stuckRed)
            }
            .padding(.top, 4)

            Button("Remove Buddygotchi…") {
                showingRemoveConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(BuddyTheme.stuckRed)
        }
    }

    // MARK: - Helpers

    private func cycleSpecies(_ direction: Int) {
        guard let idx = buddyOrder.firstIndex(of: species) else { return }
        let next = (idx + direction + buddyOrder.count) % buddyOrder.count
        species = buddyOrder[next]
        engine.setSpecies(species)
        esp32Output.sendNow()
    }

    private var serverHealthRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(serverHealthColor)
                .frame(width: 6, height: 6)
            Text("Server")
                .font(.buddy(13))
            Spacer()
            Text(serverHealthLabel)
                .font(.buddy(11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var serverHealthLabel: String {
        guard let serverHealth else { return "Unknown" }
        switch serverHealth.status {
        case .starting:
            return "Starting"
        case .listening(let port):
            return "Listening on \(port)"
        case .failed(let reason):
            return "Failed — \(reason)"
        }
    }

    private var serverHealthColor: Color {
        guard let serverHealth else { return .secondary.opacity(0.5) }
        switch serverHealth.status {
        case .starting:
            return BuddyTheme.amber
        case .listening:
            return BuddyTheme.green
        case .failed:
            return BuddyTheme.stuckRed
        }
    }

    private var bugReportErrorBinding: Binding<Bool> {
        Binding(
            get: { bugReportError != nil },
            set: { if !$0 { bugReportError = nil } }
        )
    }

    private func exportBugReport() async {
        isExportingBugReport = true
        defer { isExportingBugReport = false }

        guard let data = await engine.diagnosticLog.exportBundle(engine: engine) else {
            bugReportError = "No diagnostic data was available."
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "buddygotchi-report-\(formatter.string(from: Date.now)).json"

        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            bugReportError = "The Desktop folder could not be found."
            return
        }
        let url = desktop.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            bugReportError = "Couldn't write to Desktop: \(error.localizedDescription)"
        }
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
