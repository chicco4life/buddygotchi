import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let serverHealth: ServerHealth?
    var onOpenOnboarding: () -> Void = {}

    @State private var selection: SettingsSection? = .buddy
    var frameHeight: CGFloat = 650

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.sidebar, id: \.self, selection: $selection) { section in
                Label(BuddyCopy.phase7(section.rawValue, language: engine.state.language), systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(160)
        } detail: {
            SettingsSectionView(isPresented: $isPresented, engine: engine, esp32Output: esp32Output,
                                serverHealth: serverHealth, onOpenOnboarding: onOpenOnboarding,
                                section: selection ?? .buddy)
                .navigationTitle(BuddyCopy.phase7((selection ?? .buddy).rawValue, language: engine.state.language))
        }
        .frame(width: 760, height: frameHeight)
        .background(BuddyTheme.windowBackground)
    }
}

/// The live detail and offscreen snapshots share state, actions, and lifecycle.
struct SettingsSectionView: View {
    @Binding var isPresented: Bool
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let serverHealth: ServerHealth?
    var onOpenOnboarding: () -> Void = {}
    let section: SettingsSection

    @State private var interactiveMode = false
    @State private var soundsEnabled = true
    @State private var agentDrawingsEnabled = true

    @State private var approvalMode = false
    @AppStorage("approvalModeExplained") private var approvalModeExplained = false
    private var buddyName: String { engine.buddyName }
    private var esp32UUID: String? { engine.pairedPeripheral }
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
    @State private var showingApprovalModeExplainer = false
    var body: some View {
        Form { sectionContent(section) }
        .formStyle(.grouped)
        .onAppear {
            interactiveMode = engine.boolSetting(DefaultsKey.interactiveMode, fallback: false)
            soundsEnabled = engine.boolSetting(DefaultsKey.soundsEnabled, fallback: true)
            agentDrawingsEnabled = engine.boolSetting(DefaultsKey.agentDrawingsEnabled, fallback: true)
            approvalMode = engine.boolSetting(DefaultsKey.approvalMode, fallback: false)
            normalizeBuddySpecies()
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
            cleanupAbandonedPairing()
        }
        .onChange(of: esp32Output.connectionState) { _, state in
            if state == .connected, let selectedDeviceUUID {
                engine.setPairedPeripheral(selectedDeviceUUID)
                self.selectedDeviceUUID = nil
            }
        }
        .sheet(isPresented: $showingApprovalModeExplainer) {
            ApprovalModeExplainerSheet(
                onCancel: {
                    showingApprovalModeExplainer = false
                },
                onConfirm: {
                    approvalModeExplained = true
                    setApprovalMode(true)
                    showingApprovalModeExplainer = false
                }
            )
        }
        .sheet(isPresented: $showingFirmwareUpdate) {
            FirmwareUpdateView(
                updater: esp32Output.firmwareUpdater,
                isPresented: $showingFirmwareUpdate
            )
        }
        .alert(BuddyCopy.shared.settingsCopy.exportBugReportFailed, isPresented: bugReportErrorBinding) {
            Button(BuddyCopy.shared.common.ok, role: .cancel) {}
        } message: {
            Text(bugReportError ?? BuddyCopy.shared.settingsCopy.bugReportFallback)
        }
        .alert(BuddyCopy.shared.settingsCopy.removeBoopTitle, isPresented: $showingRemoveConfirmation) {
            Button(BuddyCopy.cancel, role: .cancel) {}
            Button(BuddyCopy.shared.settingsCopy.removeAndQuit, role: .destructive) {
                removeBoop()
            }
        } message: {
            Text(BuddyCopy.shared.settingsCopy.removeBoopMessage)
        }
        .alert(BuddyCopy.shared.settingsCopy.updatesUnavailable, isPresented: $showingUpdaterUnavailable) {
            Button(BuddyCopy.shared.common.ok, role: .cancel) {}
        } message: {
            Text(BuddyCopy.shared.settingsCopy.updatesUnavailableMessage)
        }
        .alert(BuddyCopy.shared.settingsCopy.removeFailed, isPresented: Binding(
            get: { uninstallError != nil },
            set: { if !$0 { uninstallError = nil } }
        )) {
            Button(BuddyCopy.shared.common.ok, role: .cancel) {}
        } message: {
            Text(uninstallError ?? BuddyCopy.shared.common.unknown)
        }
    }

    @ViewBuilder private func sectionContent(_ section: SettingsSection) -> some View {
        switch section {
        case .buddy:
            Section {
                LabeledContent(BuddyCopy.shared.settingsCopy.name, value: buddyName)
                companion([.language, .voice])
                BuddySettingToggle(title: BuddyCopy.shared.settingsCopy.sounds,
                    description: BuddyCopy.shared.settingsCopy.soundsDescription,
                    isOn: Binding(get: { soundsEnabled }, set: { soundsEnabled = $0; engine.setBoolSetting(DefaultsKey.soundsEnabled, $0) }))
                companion([.sounds, .profile])
            }
        case .agents: Section { agentsSection }
        case .device, .displays:
            Section { displaysSection }
            Section { companion([.retire]) }
        case .focus, .general:
            Section {
                companion([.focus])
                BuddySettingToggle(title: BuddyCopy.shared.settingsCopy.interactiveMode,
                    description: BuddyCopy.shared.settingsCopy.interactiveModeDescription,
                    isOn: Binding(get: { interactiveMode }, set: { interactiveMode = $0; engine.setBoolSetting(DefaultsKey.interactiveMode, $0) }))
                BuddySettingToggle(title: BuddyCopy.shared.settingsCopy.launchAtLogin,
                    description: BuddyCopy.shared.settingsCopy.launchAtLoginDescription, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        LoginItemManager.shared.setEnabled(value)
                        refreshLoginItemState()
                    }
                if launchAtLoginStatus == .requiresApproval {
                    Text(BuddyCopy.shared.settingsCopy.launchAtLoginApproval).foregroundStyle(.secondary)
                }
            }
        case .advanced:
            Section(BuddyCopy.phase7("approvals", language: engine.state.language)) {
                BuddySettingToggle(title: BuddyCopy.shared.settingsCopy.localApprovalMode,
                    description: BuddyCopy.shared.settingsCopy.localApprovalModeDescription, isOn: approvalModeBinding)
                companion([.quick])
            }
            Section(BuddyCopy.phase7("leaderboard", language: engine.state.language)) { companion([.leaderboard]) }
            Section(BuddyCopy.phase7("agentsCan", language: engine.state.language)) {
                BuddySettingToggle(title: BuddyCopy.shared.settingsCopy.agentDrawings,
                    description: BuddyCopy.shared.settingsCopy.agentDrawingsDescription,
                    isOn: Binding(get: { agentDrawingsEnabled }, set: { agentDrawingsEnabled = $0; engine.setBoolSetting(DefaultsKey.agentDrawingsEnabled, $0) }))
            }
            Section(BuddyCopy.phase7("diagnostics", language: engine.state.language)) {
                advancedRows
                exportBugReportRow
            }
            Section {
                aboutSection
            } header: {
                Text(BuddyCopy.phase7("about", language: engine.state.language))
            } footer: {
                Text(BuddyCopy.phase7("updatePrivacy", language: engine.state.language))
            }
            Section(BuddyCopy.phase7("reset", language: engine.state.language)) { resetRows }
        case .about: Section { aboutSection }
        default: Section { companion([section]) }
        }
    }

    private func companion(_ sections: [SettingsSection]) -> some View {
        CompanionSettings(engine: engine, device: esp32Output, onRetired: onOpenOnboarding, sections: sections)
    }

    private var advancedRows: some View {
        Group {
            serverHealthRow
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: BuddyConfig.default.stateDir))
            } label: {
                HStack {
                    Text(BuddyCopy.shared.settingsCopy.openConfigFolder)
                        .font(.body)
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        Group {

            Group {
                ForEach(AgentKind.allCases) { agent in
                    let health = agentHealth[agent] ?? .notInstalled
                    HStack {
                        Image(systemName: "terminal").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.displayName).font(.body)
                            Text(hookHealthLabel(health))
                                .font(.footnote)
                                .foregroundStyle(hookHealthColor(health))
                        }
                        Spacer()
                        if health == .installed {
                            Button(BuddyCopy.shared.common.repair) {
                                do {
                                    try HookInstaller.shared.repair(agent: agent)
                                    agentHealth[agent] = HookInstaller.shared.verify(agent: agent)
                                } catch {
                                    agentHealth[agent] = .corrupted(reason: error.localizedDescription)
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button(health.repairable ? BuddyCopy.shared.common.repair : BuddyCopy.shared.common.connect) {
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
                            .disabled(!health.repairable && !canInstall(health))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

        }
    }

    private func hookHealthLabel(_ health: HookHealth) -> String {
        switch health {
        case .installed:
            return BuddyCopy.shared.common.connected
        case .notInstalled:
            return BuddyCopy.shared.settingsCopy.notConnected
        case .outdated(let installed, let current):
            return BuddyCopy.hookNeedsRepair(installed: installed, current: current)
        case .corrupted(let reason):
            return BuddyCopy.hookNeedsRepair(reason: reason)
        }
    }

    private func hookHealthColor(_ health: HookHealth) -> Color {
        switch health {
        case .installed:
            return .green
        case .outdated, .corrupted:
            return .red
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
        Group {

            Group {
                if esp32UUID != nil {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BuddyCopy.Onboarding.hardware).font(.body)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(esp32Output.connectionState == .connected ? .green : BuddyTheme.inkFaint)
                                    .frame(width: 6, height: 6)
                                Text(BuddyCopy.phase7("device-" + esp32Output.connectionState.rawValue, language: engine.state.language))
                                    .font(.footnote)
                                    .foregroundStyle(BuddyTheme.inkSoft)
                            }
                        }
                        Spacer()
                        Button(BuddyCopy.shared.settingsCopy.forget) {
                            showingUnpairConfirmation = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .confirmationDialog(BuddyCopy.shared.settingsCopy.forgetThisBuddyTitle, isPresented: $showingUnpairConfirmation) {
                        Button(BuddyCopy.shared.settingsCopy.forgetThisBuddy, role: .destructive) {
                            engine.setPairedPeripheral(nil)
                            esp32Output.unpair()
                        }
                        Button(BuddyCopy.cancel, role: .cancel) {}
                    } message: {
                        Text(BuddyCopy.shared.settingsCopy.forgetBuddyMessage)
                    }

                    if esp32Output.connectionState == .connected {
                        firmwareRow
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BuddyCopy.Onboarding.hardware).font(.body)
                            Text(BuddyCopy.shared.settingsCopy.notPaired)
                                .font(.footnote)
                                .foregroundStyle(BuddyTheme.inkSoft)
                        }
                        Spacer()
                        Button(scanner.isScanning ? BuddyCopy.Onboarding.scanning : BuddyCopy.shared.settingsCopy.pairABuddy) {
                            if scanner.isScanning { scanner.stop() }
                            else { scanner.start() }
                        }
                        .buttonStyle(.bordered)
                    }

                    Link(destination: AppMetadata.flashURL) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(BuddyCopy.shared.settingsCopy.bareHardwareBuddy).font(.body)
                                Text(BuddyCopy.shared.settingsCopy.flashItFirst)
                                    .font(.footnote)
                                    .foregroundStyle(BuddyTheme.inkSoft)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(BuddyTheme.inkSoft)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }


            if scanner.isScanning && scanner.bluetoothUnavailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BuddyCopy.Onboarding.bluetoothOff).font(.footnote)
                        Text(BuddyCopy.Onboarding.bluetoothOffHint)
                            .font(.footnote)
                            .foregroundStyle(BuddyTheme.inkSoft)
                    }
                    Spacer()
                }

                .padding(.top, 8)
            } else if scanner.isScanning && !scanner.devices.isEmpty {
                VStack(spacing: 8) {
                    ForEach(scanner.devices, id: \.identifier) { device in
                        Button {
                            cleanupAbandonedPairing()
                            selectedDeviceUUID = device.identifier
                            scanner.stop()
                            esp32Output.connect(to: device.identifier)
                        } label: {
                            HStack {
                                Text(device.name).font(.footnote)
                                Spacer()
                                Text(BuddyCopy.shared.common.connect)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)

                        .accessibilityLabel(BuddyCopy.shared.settingsCopy.connectToDeviceTemplate.replacingOccurrences(of: "{device}", with: device.name))
                    }
                }
                .padding(.top, 8)
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
                    Text(BuddyCopy.shared.settingsCopy.firmware).font(.body)
                    Text(esp32Output.firmwareUpdater.deviceVersion ?? BuddyCopy.shared.settingsCopy.firmwareUnknown)
                        .font(.footnote)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                Spacer()
                firmwareTrailingLabel
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(firmwareAccessibilityLabel)
    }

    @ViewBuilder
    private var firmwareTrailingLabel: some View {
        switch esp32Output.firmwareUpdater.state {
        case .available(let release, _):
            HStack(spacing: 4) {
                Circle().fill(BuddyTheme.amberInk).frame(width: 6, height: 6)
                Text(BuddyCopy.shared.settingsCopy.firmwareUpdateTemplate.replacingOccurrences(of: "{version}", with: release.version))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Text(BuddyCopy.shared.settingsCopy.upToDate)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkSoft)
        case .downloading(let p), .uploading(let p, _):
            Text("\(Int(p * 100))%")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .verifying, .rebooting:
            Text(BuddyCopy.shared.settingsCopy.updating)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .success:
            Text(BuddyCopy.shared.settingsCopy.updated)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.greenInk)
        case .checkFailed:
            Text(BuddyCopy.shared.settingsCopy.cantCheckNow)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkFaint)
        case .failed:
            Text(BuddyCopy.shared.settingsCopy.failed)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.clayInk)
        case .checking, .idle:
            Text(BuddyCopy.shared.settingsCopy.checking)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkFaint)
        }
    }

    private var firmwareAccessibilityLabel: String {
        let v = esp32Output.firmwareUpdater.deviceVersion ?? BuddyCopy.shared.settingsCopy.firmwareUnknown.lowercased()
        switch esp32Output.firmwareUpdater.state {
        case .available(let r, _):
            return BuddyCopy.shared.settingsCopy.firmwareAvailableTemplate
                .replacingOccurrences(of: "{current}", with: v)
                .replacingOccurrences(of: "{next}", with: r.version)
        case .upToDate:
            return BuddyCopy.shared.settingsCopy.firmwareUpToDateTemplate.replacingOccurrences(of: "{current}", with: v)
        case .downloading, .uploading, .verifying, .rebooting:
            return BuddyCopy.shared.settingsCopy.firmwareUpdateInProgress
        case .success:
            return BuddyCopy.shared.settingsCopy.firmwareUpdated
        case .checkFailed:
            return BuddyCopy.shared.settingsCopy.firmwareCheckUnavailable
        case .failed:
            return BuddyCopy.shared.settingsCopy.firmwareUpdateFailed
        case .checking, .idle:
            return BuddyCopy.shared.settingsCopy.checkingFirmwareUpdates
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Group {

            Group {
                HStack {
                    Text(BuddyCopy.shared.settingsCopy.version).font(.body)
                    Spacer()
                    Text(AppMetadata.displayVersion)
                        .font(.body)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .accessibilityElement(children: .combine)

                Button {
                    if SparkleUpdateManager.shared.isAvailable {
                        SparkleUpdateManager.shared.checkForUpdates()
                    } else {
                        showingUpdaterUnavailable = true
                    }
                } label: {
                    HStack {
                        Text(BuddyCopy.shared.settingsCopy.checkForUpdates)
                            .font(.body)
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(BuddyTheme.inkSoft)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)

                Link(destination: AppMetadata.supportURL) {
                    HStack {
                        Text(BuddyCopy.shared.settingsCopy.helpAndSupport)
                            .font(.body)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(BuddyTheme.inkSoft)
                    }
                }
                .buttonStyle(.bordered)

            }
        }
    }

    private var exportBugReportRow: some View {
        Button {
            Task { await exportBugReport() }
        } label: {
            HStack {
                if isExportingBugReport {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(BuddyTheme.inkSoft)
                } else {
                    Image(systemName: "ladybug")
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                Text(BuddyCopy.shared.settingsCopy.exportBugReport)
                    .font(.body)
                Spacer()
            }
        }
        .buttonStyle(.bordered)

        .disabled(isExportingBugReport)
    }

    private var resetRows: some View {
        Group {
            settingsActionRow(
                BuddyCopy.runSetupAgain,
                systemImage: "arrow.counterclockwise",
                role: .normal
            ) {
                engine.restartOnboarding()
                isPresented = false
                onOpenOnboarding()
            }

            settingsActionRow(
                BuddyCopy.shared.settingsCopy.removeBoop,
                systemImage: nil,
                role: .destructive
            ) {
                showingRemoveConfirmation = true
            }
        }
    }

    private enum SettingsActionRole {
        case normal
        case destructive
    }

    private func settingsActionRow(
        _ title: String,
        systemImage: String?,
        role: SettingsActionRole,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(role == .destructive ? Color.red : BuddyTheme.ink)
                Spacer()
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    // MARK: - Helpers

    private var approvalModeBinding: Binding<Bool> {
        Binding(
            get: { approvalMode },
            set: { newValue in
                if newValue && !approvalModeExplained {
                    showingApprovalModeExplainer = true
                } else {
                    setApprovalMode(newValue)
                }
            }
        )
    }

    private func setApprovalMode(_ enabled: Bool) {
        approvalMode = enabled
        engine.setApprovalMode(enabled)
    }

    private func cleanupAbandonedPairing() {
        guard selectedDeviceUUID != nil && esp32Output.connectionState != .connected else { return }
        selectedDeviceUUID = nil
        engine.setPairedPeripheral(nil)
        esp32Output.unpair()
    }

    private var serverHealthRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(serverHealthColor)
                .frame(width: 6, height: 6)
            Text(BuddyCopy.shared.settingsCopy.server)
                .font(.body)
            Spacer()
            Text(serverHealthLabel)
                .font(.footnote)
                .foregroundStyle(BuddyTheme.inkSoft)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var serverHealthLabel: String {
        guard let serverHealth else { return BuddyCopy.phase7("serverUnreachable", language: engine.state.language) }
        switch serverHealth.status {
        case .starting:
            return BuddyCopy.shared.settingsCopy.starting
        case .listening(let port):
            return BuddyCopy.phase7("serverListening", language: engine.state.language).replacingOccurrences(of: "{port}", with: "\(port)")
        case .failed:
            return BuddyCopy.phase7("serverUnreachable", language: engine.state.language)
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
            return BuddyTheme.clay
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
            bugReportError = BuddyCopy.shared.settingsCopy.noDiagnosticData
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "boop-report-\(formatter.string(from: Date.now)).json"

        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            bugReportError = BuddyCopy.shared.settingsCopy.desktopNotFound
            return
        }
        let url = desktop.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            bugReportError = BuddyCopy.shared.settingsCopy.desktopWriteFailedTemplate.replacingOccurrences(of: "{reason}", with: error.localizedDescription)
        }
    }

    private func refreshLoginItemState() {
        launchAtLoginStatus = LoginItemManager.shared.status
        launchAtLogin = launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
    }

    private func removeBoop() {
        do {
            try ConsumerUninstaller.removeInstalledState()
            NSApplication.shared.terminate(nil)
        } catch {
            uninstallError = error.localizedDescription
        }
    }

    private func normalizeBuddySpecies(sendHeartbeat: Bool = false) {
        if engine.state.pet.species != Pet.defaultSpecies {
            engine.setSpecies(Pet.defaultSpecies)
            if sendHeartbeat {
                esp32Output.sendNow()
            }
        } else if sendHeartbeat {
            engine.setSpecies(Pet.defaultSpecies)
            esp32Output.sendNow()
        }
    }
}

private struct ApprovalModeExplainerSheet: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(BuddyCopy.shared.settingsCopy.localApprovalModeSentence)
                .font(.headline)
                .foregroundStyle(BuddyTheme.ink)

            VStack(alignment: .leading, spacing: 10) {
                explainerRow(BuddyCopy.shared.settingsCopy.approvalExplainerRow1)
                explainerRow(BuddyCopy.shared.settingsCopy.approvalExplainerRow2)
                explainerRow(BuddyCopy.shared.settingsCopy.approvalExplainerRow3)
            }

            HStack {
                Spacer()
                Button(BuddyCopy.cancel, action: onCancel)
                    .buttonStyle(.bordered)
                Button(BuddyCopy.shared.settingsCopy.turnOn, action: onConfirm)
                    .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(BuddyTheme.windowBackground)

    }

    private func explainerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(BuddyTheme.amberInk)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.callout)
                .foregroundStyle(BuddyTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
