import AppKit
import SwiftUI

struct OnboardingView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let onFinish: () -> Void

    @State private var model = OnboardingModel()
    @State private var scanner = BLEScanner()
    @State private var selectedDeviceUUID: UUID?
    @State private var pairingTask: Task<Void, Never>?
    @State private var adoptionPreviewState: PetState = .idle
    @State private var adoptionPreviewResetTask: Task<Void, Never>?
    @State private var didAutoConnect = false
    @State private var didHatch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            BuddyTheme.night.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 24)

                Group {
                    switch model.step {
                    case .hatch: hatchStep
                    case .adopt: adoptStep
                    case .agents: agentsStep
                    case .firstContact: firstContactStep
                    case .display: displayStep
                    case .done: doneStep
                    }
                }
                .id(model.step.rawValue)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(reduceMotion ? nil : .buddyEase(0.35), value: model.step.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 44)
            .padding(.bottom, 34)
        }
        .frame(width: BuddyTheme.onboardingWidth, height: BuddyTheme.onboardingHeight)
        .preferredColorScheme(.dark)
        .onExitCommand {
            model.goBack()
        }
        .onDisappear {
            scanner.stop()
            pairingTask?.cancel()
            adoptionPreviewResetTask?.cancel()
            if model.step == .display && model.selectedOutput == .hardware && esp32Output.connectionState != .connected {
                cleanupAbandonedPairing(forceUnpair: true)
            } else {
                cleanupAbandonedPairing()
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<OnboardingStep.allCases.count, id: \.self) { index in
                Capsule()
                    .fill(index <= model.step.rawValue ? BuddyTheme.amber : BuddyTheme.textPrimary.opacity(0.12))
                    .frame(width: index == model.step.rawValue ? 54 : 34, height: 5)
            }
        }
        .animation(reduceMotion ? nil : .buddyEase(0.3), value: model.step.rawValue)
        .accessibilityElement()
        .accessibilityLabel("Onboarding progress, step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    private var hatchStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 18)
            hatchStage
                .onAppear {
                    guard !reduceMotion else {
                        didHatch = true
                        return
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1300))
                        didHatch = true
                    }
                }
                .onTapGesture { didHatch = true }

            stepHeader(
                title: BuddyCopy.Onboarding.hatchTitle,
                subtitle: BuddyCopy.Onboarding.hatchSubtitle
            )

            Spacer()

            Button(BuddyCopy.Onboarding.meetBuddy) {
                model.advance()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var hatchStage: some View {
        ZStack {
            if didHatch || reduceMotion {
                BlobBuddyView(petState: .idle, size: 220)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate * .pi
                    let wobble = sin(phase) * 2

                    ZStack {
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [Color(hex: "#F7F2E9"), BuddyTheme.textPrimary, Color(hex: "#D8CCB9")],
                                    center: .topLeading,
                                    startRadius: 12,
                                    endRadius: 120
                                )
                            )
                            .frame(width: 150, height: 194)
                            .shadow(color: BuddyTheme.amber.opacity(0.22), radius: 24, y: 10)
                        CrackShape()
                            .stroke(BuddyTheme.night.opacity(0.45), lineWidth: 3)
                            .frame(width: 54, height: 72)
                            .offset(y: -10)
                    }
                    .rotationEffect(.degrees(wobble))
                }
                .transition(.opacity)
            }
        }
        .frame(height: 230)
        .animation(reduceMotion ? nil : .buddyEase(0.55), value: didHatch)
    }

    private var adoptStep: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 10)
            stepHeader(title: BuddyCopy.Onboarding.adoptTitle)

            HStack(spacing: 26) {
                Button(action: { cycleSpecies(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(OnboardingIconButtonStyle())
                .accessibilityLabel("Previous species")

                VStack(spacing: 12) {
                    Button(action: cycleAdoptionPreviewState) {
                        PetStageView(petState: adoptionPreviewState, species: model.selectedSpecies, fontSize: 24)
                            .frame(width: 260, height: 180)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(model.selectedSpecies) buddy preview, \(adoptionPreviewState.rawValue)")
                    Text(model.selectedSpecies.capitalized)
                        .font(.buddy(15, weight: .semibold))
                        .foregroundStyle(buddySpeciesColor(for: model.selectedSpecies))
                }

                Button(action: { cycleSpecies(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(OnboardingIconButtonStyle())
                .accessibilityLabel("Next species")
            }

            TextField(
                BuddyCopy.Onboarding.namePlaceholder,
                text: Binding(
                    get: { model.buddyName },
                    set: { model.buddyName = $0 }
                )
            )
                .textFieldStyle(.plain)
                .font(.buddy(15))
                .foregroundStyle(BuddyTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(BuddyTheme.nightRaised, in: RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topLeading) {
                    Text(BuddyCopy.Onboarding.nameLabel)
                        .font(.buddy(9.5, weight: .semibold))
                        .foregroundStyle(BuddyTheme.textTertiary)
                        .offset(x: 14, y: -18)
                }
                .frame(width: 320)
                .padding(.top, 6)

            Spacer()

            navigationBar(nextTitle: BuddyCopy.Onboarding.adopt)
        }
    }

    private var agentsStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            stepHeader(
                title: BuddyCopy.Onboarding.agentsTitle,
                subtitle: BuddyCopy.Onboarding.agentsSubtitle
            )

            VStack(spacing: 10) {
                ForEach(AgentKind.allCases) { agent in
                    agentRow(agent)
                }
            }
            .frame(width: 520)

            Spacer()

            HStack {
                Button("Back") { model.goBack() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())

                Button(BuddyCopy.Onboarding.skipForNow) {
                    model.advance()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())

                Spacer()

                Button("Next") { model.advance() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!model.canFinishAgents)
                    .opacity(model.canFinishAgents ? 1 : 0.45)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .onAppear {
            model.refreshAgents()
            if !didAutoConnect {
                let detected = AgentKind.allCases.filter { model.agentDetection[$0] == true }
                if detected.count == 1, model.agentInstalled[detected[0]] != true {
                    model.connect(agent: detected[0], diagnosticLog: engine.diagnosticLog)
                }
                didAutoConnect = true
            }
        }
    }

    private var firstContactStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 18)

            PetStageView(
                petState: model.heardFromAgent == nil ? .sleep : .celebrate,
                species: model.selectedSpecies,
                fontSize: 24
            )
            .frame(height: 180)

            stepHeader(
                title: model.heardFromAgent.map { "Heard from \($0.displayName)." } ?? BuddyCopy.Onboarding.firstContactTitle,
                subtitle: model.heardFromAgent == nil ? BuddyCopy.Onboarding.firstContactWaiting : nil
            )

            Button(BuddyCopy.Onboarding.copyPrompt) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(BuddyCopy.Onboarding.testPrompt, forType: .string)
            }
            .buttonStyle(OnboardingSecondaryButtonStyle())
            .opacity(model.heardFromAgent == nil ? 1 : 0)
            .disabled(model.heardFromAgent != nil)

            if model.showingTroubleshooting {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(engine.state.desktop.status == .connected ? BuddyTheme.green : BuddyTheme.stuckRed)
                        .frame(width: 9, height: 9)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BuddyCopy.Onboarding.troubleshootingTitle)
                            .font(.buddy(13, weight: .semibold))
                            .foregroundStyle(BuddyTheme.textPrimary)
                        Text(BuddyCopy.Onboarding.troubleshooting)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(width: 440)
                .background(BuddyTheme.nightRaised, in: RoundedRectangle(cornerRadius: 14))
            }

            Spacer()

            HStack {
                Button("Back") { model.goBack() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                Spacer()
                if model.heardFromAgent == nil {
                    Button("Skip") { model.advance() }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                } else {
                    Button("Next") { model.advance() }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .onAppear {
            model.firstContactStartedAt = .now
            updateHeardAgent(from: engine.state.activeSessions)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(60))
                if model.step == .firstContact && model.heardFromAgent == nil {
                    model.showingTroubleshooting = true
                }
            }
        }
        .onChange(of: engine.state.activeSessions) { _, sessions in
            updateHeardAgent(from: sessions)
        }
    }

    private var displayStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 14)
            stepHeader(
                title: BuddyCopy.Onboarding.displayTitle,
                subtitle: BuddyCopy.Onboarding.displaySubtitle
            )

            VStack(spacing: 10) {
                outputRow(.thisMac)
                outputRow(.hardware)
            }
            .frame(width: 540)

            if model.selectedOutput == .hardware {
                Text(BuddyCopy.Onboarding.hardwareFootnote)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(width: 460)
                blePairingPanel
            }

            Spacer()

            navigationBar(nextDisabled: model.selectedOutput == .hardware && esp32Output.connectionState != .connected)
        }
        .onAppear {
            if model.selectedOutput == .hardware {
                startScanning()
            }
        }
        .onChange(of: model.selectedOutput) { _, output in
            if output == .hardware {
                startScanning()
            } else {
                scanner.stop()
                cleanupAbandonedPairing(forceUnpair: true)
            }
        }
        .onChange(of: esp32Output.connectionState) { _, state in
            if state == .connected, let selectedDeviceUUID {
                UserDefaults.standard.set(selectedDeviceUUID.uuidString, forKey: esp32PeripheralUUIDKey)
                pairingTask?.cancel()
                model.pairingTimedOut = false
                esp32Output.sendTestCelebrate()
            }
        }
        .onChange(of: model.step) { oldStep, _ in
            if oldStep == .display && esp32Output.connectionState != .connected {
                cleanupAbandonedPairing(forceUnpair: true)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            adoptionCard

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuddyCopy.Onboarding.launchAtLogin)
                            .font(.buddy(13, weight: .semibold))
                            .foregroundStyle(BuddyTheme.textPrimary)
                        Text(model.isPackagedApp ? BuddyCopy.Onboarding.launchAtLoginDescription : BuddyCopy.Onboarding.launchAtLoginUnavailable)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.textTertiary)
                    }
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.launchAtLogin = $0 }
                        )
                    )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(BuddyTheme.amber)
                        .disabled(!model.isPackagedApp)
                }

                Divider().overlay(BuddyTheme.textPrimary.opacity(0.08))

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuddyCopy.Onboarding.notificationsTitle)
                            .font(.buddy(13, weight: .semibold))
                            .foregroundStyle(BuddyTheme.textPrimary)
                        Text(BuddyCopy.Onboarding.notificationsDescription)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.textTertiary)
                    }
                    Spacer()
                    if model.notificationRequested {
                        Button(BuddyCopy.Onboarding.notificationsEnabled) {}
                            .buttonStyle(OnboardingSecondaryButtonStyle())
                            .disabled(true)
                    } else {
                        Button(BuddyCopy.Onboarding.enableNotifications) {
                            NotificationManager.shared.requestPermission()
                            UserDefaults.standard.set(true, forKey: DefaultsKey.notificationPermissionRequested)
                            model.notificationRequested = true
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                    }
                }
            }
            .padding(16)
            .frame(width: 520)
            .background(BuddyTheme.nightRaised, in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            HStack {
                Button("Back") { model.goBack() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                Spacer()
                Button(BuddyCopy.Onboarding.startWatching) {
                    model.complete()
                    engine.setSpecies(model.selectedSpecies)
                    onFinish()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var adoptionCard: some View {
        HStack(spacing: 22) {
            PetStageView(petState: .idle, species: model.selectedSpecies, fontSize: 20)
                .frame(width: 160, height: 130)

            VStack(alignment: .leading, spacing: 10) {
                Text(BuddyCopy.Onboarding.doneTitle)
                    .font(.buddy(22, weight: .semibold))
                    .foregroundStyle(BuddyTheme.textPrimary)
                Text(model.displayName)
                    .font(.buddy(34, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amber)

                chipRow(title: "Species", value: model.selectedSpecies.capitalized)
                chipRow(title: "Agents", value: model.installedAgents.isEmpty ? "Skipped" : model.installedAgents.map(\.displayName).joined(separator: ", "))
                chipRow(title: "Display", value: model.selectedOutput.displayName)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 560)
        .background(BuddyTheme.nightRaised, in: RoundedRectangle(cornerRadius: 18))
    }

    private func chipRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.buddy(9.5, weight: .semibold))
                .foregroundStyle(BuddyTheme.textTertiary)
            Text(value)
                .font(.buddy(11, weight: .semibold))
                .foregroundStyle(BuddyTheme.textSecondary)
        }
    }

    private func agentRow(_ agent: AgentKind) -> some View {
        let detected = model.agentDetection[agent] ?? false
        let installed = model.agentInstalled[agent] ?? false
        let error = model.agentErrors[agent]

        return HStack(spacing: 14) {
            Circle()
                .fill(installed ? BuddyTheme.green : detected ? BuddyTheme.amber : BuddyTheme.textTertiary)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.displayName)
                    .font(.buddy(13, weight: .semibold))
                    .foregroundStyle(BuddyTheme.textPrimary)
                Text(error ?? (detected ? BuddyCopy.Onboarding.detected : BuddyCopy.Onboarding.notDetectedHint))
                    .font(.buddy(11))
                    .foregroundStyle(error == nil ? BuddyTheme.textTertiary : BuddyTheme.stuckRed)
            }

            Spacer()

            if installed {
                Button(BuddyCopy.Onboarding.connected) {}
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                    .disabled(true)
            } else {
                Button(BuddyCopy.Onboarding.connect) {
                    model.connect(agent: agent, diagnosticLog: engine.diagnosticLog)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(BuddyTheme.nightRaised, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.displayName), \(installed ? BuddyCopy.Onboarding.connected : detected ? BuddyCopy.Onboarding.detected : BuddyCopy.Onboarding.notDetected)")
    }

    private func outputRow(_ target: BuddyOutputTarget) -> some View {
        Button {
            model.selectedOutput = target
        } label: {
            HStack(spacing: 14) {
                Image(systemName: model.selectedOutput == target ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(model.selectedOutput == target ? BuddyTheme.amber : BuddyTheme.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.buddy(13, weight: .semibold))
                        .foregroundStyle(BuddyTheme.textPrimary)
                    Text(target.description)
                        .font(.buddy(11))
                        .foregroundStyle(BuddyTheme.textTertiary)
                }
                Spacer()
            }
            .padding(14)
            .background(BuddyTheme.nightRaised, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var blePairingPanel: some View {
        VStack(spacing: 10) {
            if esp32Output.connectionState == .connected && selectedDeviceUUID != nil {
                Label(BuddyCopy.Onboarding.connectedCheered, systemImage: "checkmark.circle.fill")
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.green)
            } else if model.pairingTimedOut {
                Text(BuddyCopy.Onboarding.pairingTimeout)
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.stuckRed)
                HStack {
                    Button(BuddyCopy.Onboarding.retry) {
                        retryPairing()
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    Button(BuddyCopy.Onboarding.backToList) {
                        cleanupAbandonedPairing()
                        startScanning()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            } else if selectedDeviceUUID != nil {
                ProgressView()
                    .tint(BuddyTheme.amber)
                Text(BuddyCopy.Onboarding.connecting)
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.textPrimary)
                Text(BuddyCopy.Onboarding.pairingHelp)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.textTertiary)
                    .multilineTextAlignment(.center)
            } else {
                bleDeviceList
            }
        }
        .padding(14)
        .frame(width: 480)
        .frame(minHeight: 96)
        .background(BuddyTheme.nightRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    private var bleDeviceList: some View {
        VStack(spacing: 8) {
            if scanner.devices.isEmpty {
                ProgressView()
                    .tint(BuddyTheme.amber)
                Text(BuddyCopy.Onboarding.scanning)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.textSecondary)
            } else {
                ForEach(scanner.devices, id: \.identifier) { device in
                    Button {
                        chooseDevice(device.identifier)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.buddy(11, weight: .semibold))
                                    .foregroundStyle(BuddyTheme.textPrimary)
                                Text(String(device.identifier.uuidString.prefix(8)) + "…")
                                    .font(.buddy(11))
                                    .foregroundStyle(BuddyTheme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BuddyTheme.textTertiary)
                        }
                        .padding(10)
                        .background(BuddyTheme.nightRaised2, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func navigationBar(nextTitle: String = "Next", nextDisabled: Bool = false) -> some View {
        HStack {
            Button("Back") { model.goBack() }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            Spacer()
            Button(nextTitle) { model.advance() }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.45 : 1)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func stepHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.buddy(34, weight: .semibold))
                .foregroundStyle(BuddyTheme.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.buddy(13))
                    .foregroundStyle(BuddyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
    }

    private func cycleSpecies(_ direction: Int) {
        guard let index = buddyOrder.firstIndex(of: model.selectedSpecies) else {
            model.selectedSpecies = Pet.defaultSpecies
            engine.setSpecies(model.selectedSpecies)
            return
        }
        let next = (index + direction + buddyOrder.count) % buddyOrder.count
        model.selectedSpecies = buddyOrder[next]
        engine.setSpecies(model.selectedSpecies)
        adoptionPreviewResetTask?.cancel()
        adoptionPreviewState = .idle
    }

    private func updateHeardAgent(from sessions: [SessionSnapshot]) {
        guard model.heardFromAgent == nil, let source = sessions.first?.source else { return }
        model.heardFromAgent = AgentKind(rawValue: source)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2500))
            if model.step == .firstContact {
                model.advance()
            }
        }
    }

    private func startScanning() {
        selectedDeviceUUID = nil
        model.pairingTimedOut = false
        pairingTask?.cancel()
        scanner.start()
    }

    private func chooseDevice(_ uuid: UUID) {
        selectedDeviceUUID = uuid
        model.pairingTimedOut = false
        scanner.stop()
        esp32Output.connect(to: uuid)
        startPairingTimeout()
    }

    private func retryPairing() {
        guard let uuid = selectedDeviceUUID else {
            startScanning()
            return
        }
        model.pairingTimedOut = false
        esp32Output.connect(to: uuid)
        startPairingTimeout()
    }

    private func startPairingTimeout() {
        pairingTask?.cancel()
        pairingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if model.step == .display && model.selectedOutput == .hardware && esp32Output.connectionState != .connected {
                model.pairingTimedOut = true
            }
        }
    }

    private func cleanupAbandonedPairing(forceUnpair: Bool = false) {
        guard forceUnpair || selectedDeviceUUID != nil || model.pairingTimedOut else { return }
        pairingTask?.cancel()
        pairingTask = nil
        selectedDeviceUUID = nil
        model.pairingTimedOut = false
        if forceUnpair || esp32Output.connectionState != .connected {
            UserDefaults.standard.removeObject(forKey: esp32PeripheralUUIDKey)
            esp32Output.unpair()
        }
    }

    private func cycleAdoptionPreviewState() {
        adoptionPreviewResetTask?.cancel()
        switch adoptionPreviewState {
        case .idle:
            adoptionPreviewState = .attention
        case .attention:
            adoptionPreviewState = .celebrate
            adoptionPreviewResetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1400))
                if adoptionPreviewState == .celebrate {
                    adoptionPreviewState = .idle
                }
            }
        default:
            adoptionPreviewState = .idle
        }
    }
}

private struct CrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 12, y: rect.minY + 8))
        path.addLine(to: CGPoint(x: rect.midX + 3, y: rect.minY + 24))
        path.addLine(to: CGPoint(x: rect.midX - 6, y: rect.minY + 40))
        path.addLine(to: CGPoint(x: rect.midX + 14, y: rect.minY + 62))
        return path
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(13, weight: .semibold))
            .foregroundStyle(BuddyTheme.night)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? BuddyTheme.amberDeep : BuddyTheme.amber, in: Capsule())
            .animation(.buddyEase(0.15), value: configuration.isPressed)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buddy(13, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? BuddyTheme.textPrimary : BuddyTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}

private struct OnboardingIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? BuddyTheme.textPrimary : BuddyTheme.textSecondary)
            .background(BuddyTheme.nightRaised, in: Circle())
            .animation(.buddyEase(0.15), value: configuration.isPressed)
    }
}
