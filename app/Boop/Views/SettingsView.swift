import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let serverHealth: ServerHealth?
    var onOpenOnboarding: () -> Void = {}

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
    @State private var advancedExpanded = false

    /// Overridable so the snapshot renderer can capture the full scroll content.
    var frameHeight: CGFloat = BuddyTheme.popoverHeight

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { isPresented = false }) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .alignmentGuide(.firstTextBaseline) { context in
                                context[VerticalAlignment.center] + 4
                            }
                        Text(BuddyCopy.settings)
                            .font(.buddy(15, weight: .semibold))
                    }
                }
                .buttonStyle(BuddyPlainButtonStyle())
                .accessibilityLabel(BuddyCopy.shared.settingsCopy.backToLiveView)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            BuddyDivider(inset: 16)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CompanionSettings(engine: engine, device: esp32Output, onRetired: onOpenOnboarding)
                    ForEach(SettingsSection.standard, id: \.self) { section in self.section(section) }

                }
                .padding()
            }
        }
        .frame(width: BuddyTheme.popoverWidth, height: frameHeight)

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

    @ViewBuilder func section(_ section: SettingsSection) -> some View {
        switch section {
        case .general: generalSection
        case .buddy: buddySection
        case .agents: agentsSection
        case .displays: displaysSection
        case .about: aboutSection
        default: CompanionSettings(engine: engine, device: esp32Output, onRetired: onOpenOnboarding, sections: [section])
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BuddySectionHeader(BuddyCopy.shared.settingsCopy.general)

            VStack(spacing: 0) {
                BuddySettingToggle(
                    title: BuddyCopy.shared.settingsCopy.launchAtLogin,
                    description: BuddyCopy.shared.settingsCopy.launchAtLoginDescription,
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.shared.setEnabled(newValue)
                    refreshLoginItemState()
                }

                BuddyDivider(inset: 12)

                if launchAtLoginStatus == .requiresApproval {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(BuddyTheme.amberInk)
                        Text(BuddyCopy.shared.settingsCopy.launchAtLoginApproval)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.inkSoft)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    BuddyDivider(inset: 12)
                }

                BuddySettingToggle(
                    title: BuddyCopy.shared.settingsCopy.interactiveMode,
                    description: BuddyCopy.shared.settingsCopy.interactiveModeDescription,
                    isOn: Binding(get: { interactiveMode }, set: { interactiveMode = $0; engine.setBoolSetting(DefaultsKey.interactiveMode, $0) })
                )

                BuddyDivider(inset: 12)

                BuddySettingToggle(
                    title: BuddyCopy.shared.settingsCopy.sounds,
                    description: BuddyCopy.shared.settingsCopy.soundsDescription,
                    isOn: Binding(get: { soundsEnabled }, set: { soundsEnabled = $0; engine.setBoolSetting(DefaultsKey.soundsEnabled, $0) })
                )

                BuddyDivider(inset: 12)

                BuddySettingToggle(
                    title: BuddyCopy.shared.settingsCopy.agentDrawings,
                    description: BuddyCopy.shared.settingsCopy.agentDrawingsDescription,
                    isOn: Binding(get: { agentDrawingsEnabled }, set: { agentDrawingsEnabled = $0; engine.setBoolSetting(DefaultsKey.agentDrawingsEnabled, $0) })
                )

                BuddyDivider(inset: 12)

                BuddySettingToggle(
                    title: BuddyCopy.shared.settingsCopy.localApprovalMode,
                    description: BuddyCopy.shared.settingsCopy.localApprovalModeDescription,
                    isOn: approvalModeBinding
                )

                BuddyDivider(inset: 12)

                Button {
                    withAnimation(.buddyEase(0.25)) {
                        advancedExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(BuddyCopy.shared.settingsCopy.advanced)
                            .font(.buddy(13))
                            .foregroundStyle(BuddyTheme.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(BuddyTheme.inkSoft)
                            .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BuddyPlainButtonStyle())

                if advancedExpanded {
                    advancedRows
                        .transition(.opacity)
                }
            }
            .buddyGroupedCard()
        }
    }

    private var advancedRows: some View {
        VStack(spacing: 0) {
            BuddyDivider(inset: 12)
            HStack {
                Text(BuddyCopy.shared.settingsCopy.httpPort)
                    .font(.buddy(13))
                Spacer()
                Text("\(BuddyConfig.default.httpPort)")
                    .font(.buddy(13))
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)

            BuddyDivider(inset: 12)
            serverHealthRow

            BuddyDivider(inset: 12)
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: BuddyConfig.default.stateDir))
            } label: {
                HStack {
                    Text(BuddyCopy.shared.settingsCopy.openConfigFolder)
                        .font(.buddy(13))
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(BuddyPlainButtonStyle())
        }
    }

    // MARK: - Buddy

    private var buddySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BuddySectionHeader(BuddyCopy.shared.settingsCopy.buddy)

            VStack(alignment: .leading, spacing: 6) {
                Text(BuddyCopy.shared.settingsCopy.name)
                    .font(.buddy(9.5, weight: .semibold))
                    .foregroundStyle(BuddyTheme.inkFaint)
                    .padding(.leading, 2)

                TextField(
                    BuddyCopy.shared.settingsCopy.buddyName,
                    text: .constant(buddyName)
                ).disabled(true)
                    .textFieldStyle(.plain)
                    .font(.buddy(13))
                    .foregroundStyle(BuddyTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .buddySurface(BuddyTheme.paperSunken)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            BuddySectionHeader(BuddyCopy.shared.settingsCopy.agents)

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
                            Button(BuddyCopy.shared.common.repair) {
                                do {
                                    try HookInstaller.shared.repair(agent: agent)
                                    agentHealth[agent] = HookInstaller.shared.verify(agent: agent)
                                } catch {
                                    agentHealth[agent] = .corrupted(reason: error.localizedDescription)
                                }
                            }
                            .buttonStyle(BuddyChipButtonStyle(tone: BuddyTheme.amberInk))
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
                            .buttonStyle(BuddyChipButtonStyle(tone: BuddyTheme.amberInk))
                            .disabled(!health.repairable && !canInstall(health))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .accessibilityElement(children: .combine)

                    if index < AgentKind.allCases.count - 1 {
                        BuddyDivider(inset: 12)
                    }
                }
            }
            .buddyGroupedCard()
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
            return BuddyTheme.amber
        case .outdated, .corrupted:
            return BuddyTheme.amber
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
        VStack(alignment: .leading, spacing: 0) {
            BuddySectionHeader(BuddyCopy.shared.settingsCopy.displays)

            VStack(spacing: 0) {
                HStack {
                    Text(BuddyCopy.Onboarding.thisMac).font(.buddy(13))
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BuddyTheme.amberInk)
                        Text(BuddyCopy.shared.settingsCopy.active)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.amberInk)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(BuddyCopy.shared.settingsCopy.thisMacActive)

                BuddyDivider(inset: 12)

                if esp32UUID != nil {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BuddyCopy.Onboarding.hardware).font(.buddy(13))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(esp32Output.connectionState == .connected ? BuddyTheme.amber : BuddyTheme.inkFaint)
                                    .frame(width: 6, height: 6)
                                Text(esp32Output.connectionState.rawValue)
                                    .font(.buddy(11))
                                    .foregroundStyle(BuddyTheme.inkSoft)
                            }
                        }
                        Spacer()
                        Button(BuddyCopy.shared.settingsCopy.forget) {
                            showingUnpairConfirmation = true
                        }
                        .buttonStyle(BuddyChipButtonStyle(tone: BuddyTheme.clayInk))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
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
                        BuddyDivider(inset: 12)
                        firmwareRow
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BuddyCopy.Onboarding.hardware).font(.buddy(13))
                            Text(BuddyCopy.shared.settingsCopy.notPaired)
                                .font(.buddy(11))
                                .foregroundStyle(BuddyTheme.inkSoft)
                        }
                        Spacer()
                        Button(scanner.isScanning ? BuddyCopy.Onboarding.scanning : BuddyCopy.shared.settingsCopy.pairABuddy) {
                            if scanner.isScanning { scanner.stop() }
                            else { scanner.start() }
                        }
                        .buttonStyle(BuddyChipButtonStyle(tone: BuddyTheme.amberInk))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    BuddyDivider(inset: 12)

                    Link(destination: AppMetadata.flashURL) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(BuddyCopy.shared.settingsCopy.bareHardwareBuddy).font(.buddy(13))
                                Text(BuddyCopy.shared.settingsCopy.flashItFirst)
                                    .font(.buddy(11))
                                    .foregroundStyle(BuddyTheme.inkSoft)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(BuddyTheme.inkSoft)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(BuddyPlainButtonStyle())
                }
            }
            .buddyGroupedCard()

            if scanner.isScanning && scanner.bluetoothUnavailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BuddyTheme.amberInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BuddyCopy.Onboarding.bluetoothOff).font(.buddy(11))
                        Text(BuddyCopy.Onboarding.bluetoothOffHint)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.inkSoft)
                    }
                    Spacer()
                }
                .buddyCard()
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
                                Text(device.name).font(.buddy(11))
                                Spacer()
                                Text(BuddyCopy.shared.common.connect)
                                    .font(.buddy(11))
                                    .foregroundStyle(BuddyTheme.amberInk)
                            }
                        }
                        .buttonStyle(BuddyPlainButtonStyle())
                        .buddyCard()
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
                    Text(BuddyCopy.shared.settingsCopy.firmware).font(.buddy(13))
                    Text(esp32Output.firmwareUpdater.deviceVersion ?? BuddyCopy.shared.settingsCopy.firmwareUnknown)
                        .font(.buddy(11))
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                Spacer()
                firmwareTrailingLabel
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
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
                Circle().fill(BuddyTheme.amberInk).frame(width: 6, height: 6)
                Text(BuddyCopy.shared.settingsCopy.firmwareUpdateTemplate.replacingOccurrences(of: "{version}", with: release.version))
                    .font(.buddy(9.5, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amberInk)
            }
        case .upToDate:
            Text(BuddyCopy.shared.settingsCopy.upToDate)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.inkSoft)
        case .downloading(let p), .uploading(let p, _):
            Text("\(Int(p * 100))%")
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.amberInk)
        case .verifying, .rebooting:
            Text(BuddyCopy.shared.settingsCopy.updating)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.amberInk)
        case .success:
            Text(BuddyCopy.shared.settingsCopy.updated)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.greenInk)
        case .checkFailed:
            Text(BuddyCopy.shared.settingsCopy.cantCheckNow)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.inkFaint)
        case .failed:
            Text(BuddyCopy.shared.settingsCopy.failed)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.clayInk)
        case .checking, .idle:
            Text(BuddyCopy.shared.settingsCopy.checking)
                .font(.buddy(11))
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
        VStack(alignment: .leading, spacing: 0) {
            BuddySectionHeader(BuddyCopy.shared.settingsCopy.about)

            VStack(spacing: 0) {
                HStack {
                    Text(BuddyCopy.shared.settingsCopy.version).font(.buddy(13))
                    Spacer()
                    Text(AppMetadata.displayVersion)
                        .font(.buddy(13))
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)

                BuddyDivider(inset: 12)

                Button {
                    if SparkleUpdateManager.shared.isAvailable {
                        SparkleUpdateManager.shared.checkForUpdates()
                    } else {
                        showingUpdaterUnavailable = true
                    }
                } label: {
                    HStack {
                        Text(BuddyCopy.shared.settingsCopy.checkForUpdates)
                            .font(.buddy(13))
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(BuddyTheme.inkSoft)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BuddyPlainButtonStyle())

                BuddyDivider(inset: 12)

                Link(destination: AppMetadata.supportURL) {
                    HStack {
                        Text(BuddyCopy.shared.settingsCopy.helpAndSupport)
                            .font(.buddy(13))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                            .foregroundStyle(BuddyTheme.inkSoft)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .buttonStyle(BuddyPlainButtonStyle())

                BuddyDivider(inset: 12)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock")
                        .foregroundStyle(BuddyTheme.inkSoft)
                    Text(BuddyCopy.shared.settingsCopy.updatePrivacy)
                        .font(.buddy(11))
                        .foregroundStyle(BuddyTheme.inkSoft)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .buddyGroupedCard()

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
                        .font(.buddy(13))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .buddyGroupedCard()
            .disabled(isExportingBugReport)
            .padding(.top, 10)

            Text(BuddyCopy.shared.settingsCopy.localPrivacy)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.vertical, 12)

            VStack(spacing: 0) {
                settingsActionRow(
                    BuddyCopy.runSetupAgain,
                    systemImage: "arrow.counterclockwise",
                    role: .normal
                ) {
                    engine.restartOnboarding()
                    isPresented = false
                    onOpenOnboarding()
                }

                BuddyDivider(inset: 12)

                settingsActionRow(BuddyCopy.quitBoop, systemImage: nil, role: .normal) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buddyGroupedCard()

            VStack(spacing: 0) {
                settingsActionRow(
                    BuddyCopy.shared.settingsCopy.removeBoop,
                    systemImage: nil,
                    role: .destructive
                ) {
                    showingRemoveConfirmation = true
                }
            }
            .buddyGroupedCard()
            .padding(.top, 10)
            .padding(.bottom, 8)
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
                    .font(.buddy(13))
                    .foregroundStyle(role == .destructive ? BuddyTheme.clay : BuddyTheme.ink)
                Spacer()
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(BuddyPlainButtonStyle())
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
                .font(.buddy(13))
            Spacer()
            Text(serverHealthLabel)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.inkSoft)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var serverHealthLabel: String {
        guard let serverHealth else { return BuddyCopy.shared.common.unknown }
        switch serverHealth.status {
        case .starting:
            return BuddyCopy.shared.settingsCopy.starting
        case .listening(let port):
            return BuddyCopy.shared.settingsCopy.listeningTemplate.replacingOccurrences(of: "{port}", with: "\(port)")
        case .failed(let reason):
            return BuddyCopy.shared.settingsCopy.failedReasonTemplate.replacingOccurrences(of: "{reason}", with: reason)
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
                .font(.buddy(18, weight: .semibold))
                .foregroundStyle(BuddyTheme.ink)

            VStack(alignment: .leading, spacing: 10) {
                explainerRow(BuddyCopy.shared.settingsCopy.approvalExplainerRow1)
                explainerRow(BuddyCopy.shared.settingsCopy.approvalExplainerRow2)
                explainerRow(BuddyCopy.shared.settingsCopy.approvalExplainerRow3)
            }

            HStack {
                Spacer()
                Button(BuddyCopy.cancel, action: onCancel)
                    .buttonStyle(BuddyPlainButtonStyle())
                Button(BuddyCopy.shared.settingsCopy.turnOn, action: onConfirm)
                    .buttonStyle(BuddyPrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 380)
        .background(BuddyTheme.paper)

    }

    private func explainerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(BuddyTheme.amberInk)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.buddy(12))
                .foregroundStyle(BuddyTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
