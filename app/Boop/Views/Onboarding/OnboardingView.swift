import AppKit
import SwiftUI

struct OnboardingView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let onFinish: () -> Void

    @State private var model: OnboardingModel
    @State private var scanner = BLEScanner()
    @State private var selectedDeviceUUID: UUID?
    @State private var pairingTask: Task<Void, Never>?
    @State private var wakeRequested = false
    @Environment(\.snapshotFrozen) private var snapshotFrozen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(defaults: UserDefaults = .standard, engine: BuddyEngine, esp32Output: ESP32Output, onFinish: @escaping () -> Void) {
        self.engine = engine
        self.esp32Output = esp32Output
        self.onFinish = onFinish
        _model = State(initialValue: OnboardingModel(defaults: defaults))
    }

    var body: some View {
        ZStack {
            BuddyTheme.windowBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 24)

                Group {
                    switch model.step {
                    case .welcome: welcomeStep
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

        .onAppear {
            normalizeSelectedSpecies()
        }
        .onExitCommand {
            model.goBack()
        }
        .onDisappear {
            scanner.stop()
            pairingTask?.cancel()
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
                    .fill(index <= model.step.rawValue ? BuddyTheme.amber : BuddyTheme.ink.opacity(0.12))
                    .frame(width: index == model.step.rawValue ? 54 : 34, height: 5)
            }
        }
        .animation(reduceMotion ? nil : .buddyEase(0.3), value: model.step.rawValue)
        .accessibilityElement()
        .accessibilityLabel(onboardingProgressLabel)
    }

    private var onboardingProgressLabel: String {
        BuddyCopy.shared.onboarding.progressTemplate
            .replacingOccurrences(of: "{current}", with: "\(model.step.rawValue + 1)")
            .replacingOccurrences(of: "{total}", with: "\(OnboardingStep.allCases.count)")
    }

    /// Was two steps: a hatching egg with no information in it, and a step whose
    /// only live control was this text field.
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 18)

            stepHeader(
                title: BuddyCopy.Onboarding.welcomeTitle,
                subtitle: BuddyCopy.Onboarding.welcomeSubtitle
            )

            Image(systemName: "display").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 260, height: 200)

            Spacer()

            Button(BuddyCopy.phase7("continue", language: engine.state.language)) {
                wakeRequested = true
            }
            .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
            .disabled(model.waking)
            .task(id: wakeRequested) {
                if wakeRequested && !snapshotFrozen { await model.firstWake(reduceMotion: reduceMotion); wakeRequested = false }
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var agentsStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            stepHeader(
                title: BuddyCopy.Onboarding.agentsTitle,
                subtitle: BuddyCopy.Onboarding.agentsSubtitle
            )
            Image(systemName: "display").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 150, height: 100)


            VStack(spacing: 10) {
                ForEach(AgentKind.allCases) { agent in
                    VStack(alignment: .leading, spacing: 4) {
                        agentRow(agent)
                        if model.heardAgents.contains(agent) { Text(BuddyCopy.heardFrom(agent.displayName)).font(.body).foregroundStyle(BuddyTheme.greenInk) }
                    }
                }
            }
            .frame(width: 520)

            Spacer()

            HStack {
                HStack(spacing: 12) {
                    Button(BuddyCopy.shared.onboarding.back) { model.goBack() }
                        .buttonStyle(.plain)

                    Button(BuddyCopy.Onboarding.skipForNow) {
                        model.advance()
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(BuddyCopy.phase7("continue", language: engine.state.language)) { model.advance() }
                    .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
                    .disabled(!model.canFinishAgents)
                    .opacity(model.canFinishAgents ? 1 : 0.45)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .onChange(of: model.heardEveryAgent ? nil : engine.diagnosticLog.appendedCount, initial: true) { _, _ in
            if !snapshotFrozen { model.observe(engine.diagnosticLog) }
        }
        .onAppear {
            guard !snapshotFrozen else { return }
            model.refreshAgents()
        }
    }


    private var firstContactStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "display").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary).frame(width: 240, height: 180)
            stepHeader(title: BuddyCopy.phase7("name", language: engine.state.language), subtitle: BuddyCopy.phase7("namePermanent", language: engine.state.language))
            TextField(BuddyCopy.Onboarding.namePlaceholder, text: Binding(get: { model.buddyName }, set: { model.buddyName = $0.prefix(utf8Bytes: 23) }))
                .textFieldStyle(.roundedBorder).frame(width: 320).disabled(model.nameIsLocked)
            Spacer()
            Button(BuddyCopy.phase7("continue", language: engine.state.language)) { if model.saveName() { engine.refreshSettings(); esp32Output.refreshSnapshot(); model.advance() } }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
                .disabled(model.buddyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    .font(.body)
                    .foregroundStyle(BuddyTheme.inkFaint)
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
            Image(systemName: "display").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary).frame(width: 240, height: 180)
            Text(BuddyCopy.phase7("firstOne", language: engine.state.language)).font(.headline)

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuddyCopy.Onboarding.launchAtLogin)
                            .font(.headline)
                            .foregroundStyle(BuddyTheme.ink)
                        Text(model.isPackagedApp ? BuddyCopy.Onboarding.launchAtLoginDescription : BuddyCopy.Onboarding.launchAtLoginUnavailable)
                            .font(.body)
                            .foregroundStyle(BuddyTheme.inkFaint)
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
                        .tint(BuddyTheme.amberInk)
                        .disabled(!model.isPackagedApp)
                }
                .tint(BuddyTheme.amberInk)

                BuddyDivider()

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuddyCopy.Onboarding.notificationsTitle)
                            .font(.headline)
                            .foregroundStyle(BuddyTheme.ink)
                        Text(BuddyCopy.Onboarding.notificationsDescription)
                            .font(.body)
                            .foregroundStyle(BuddyTheme.inkFaint)
                    }
                    Spacer()
                    if model.notificationRequested {
                        Button(BuddyCopy.Onboarding.notificationsEnabled) {}
                            .buttonStyle(.plain)
                            .disabled(true)
                    } else {
                        Button(BuddyCopy.Onboarding.enableNotifications) {
                            NotificationManager.shared.requestPermission()
                            UserDefaults.standard.set(true, forKey: DefaultsKey.notificationPermissionRequested)
                            model.notificationRequested = true
                        }
                        .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
                    }
                }
            }
            .padding(16)
            .frame(width: 520)


            Spacer()

            HStack {
                Button(BuddyCopy.shared.onboarding.back) { model.goBack() }
                    .buttonStyle(.plain)
                Spacer()
                Button(BuddyCopy.Onboarding.startWatching) {
                    model.complete()
                    engine.refreshSettings()
                    engine.setSpecies(model.selectedSpecies)
                    onFinish()
                }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
                .keyboardShortcut(.return, modifiers: [])
            }
        }.onAppear { if !snapshotFrozen { engine.firstCheer() } }
    }

    private func agentRow(_ agent: AgentKind) -> some View {
        let detected = model.agentDetection[agent] ?? false
        let installed = model.agentInstalled[agent] ?? false
        let error = model.agentErrors[agent]

        return HStack(spacing: 14) {
            Circle()
                .fill(installed ? BuddyTheme.green : detected ? BuddyTheme.amber : BuddyTheme.inkFaint)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.displayName)
                    .font(.headline)
                    .foregroundStyle(BuddyTheme.ink)
                Text(error ?? (detected ? BuddyCopy.Onboarding.detected : BuddyCopy.Onboarding.notDetectedHint))
                    .font(.body)
                    .foregroundStyle(error == nil ? BuddyTheme.inkFaint : BuddyTheme.clay)
            }

            Spacer()

            if installed {
                Button(BuddyCopy.Onboarding.connected) {}
                    .buttonStyle(.plain)
                    .disabled(true)
            } else {
                Button(BuddyCopy.Onboarding.connect) {
                    model.connect(agent: agent, diagnosticLog: engine.diagnosticLog)
                }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
            }
        }
        .padding(14)

        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.displayName), \(installed ? BuddyCopy.Onboarding.connected : detected ? BuddyCopy.Onboarding.detected : BuddyCopy.Onboarding.notDetected)")
    }

    private func outputRow(_ target: BuddyOutputTarget) -> some View {
        Button {
            model.selectedOutput = target
        } label: {
            HStack(spacing: 14) {
                outputSelectionIndicator(selected: model.selectedOutput == target)
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.displayName)
                        .font(.headline)
                        .foregroundStyle(BuddyTheme.ink)
                    Text(target.description)
                        .font(.body)
                        .foregroundStyle(BuddyTheme.inkFaint)
                }
                Spacer()
            }
            .padding(14)

        }
        .buttonStyle(.plain)
    }

    private func outputSelectionIndicator(selected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(selected ? BuddyTheme.amber : BuddyTheme.inkSoft, lineWidth: selected ? 0 : 1.5)
                .frame(width: 20, height: 20)
            if selected {
                Circle()
                    .fill(BuddyTheme.amber)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(BuddyTheme.ink)
            }
        }
        .frame(width: 20, height: 20)
    }

    private var blePairingPanel: some View {
        VStack(spacing: 10) {
            if esp32Output.connectionState == .connected && selectedDeviceUUID != nil {
                Label(BuddyCopy.Onboarding.connectedCheered, systemImage: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(BuddyTheme.greenInk)
            } else if model.pairingTimedOut {
                Text(BuddyCopy.Onboarding.pairingTimeout)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.clayInk)
                HStack {
                    Button(BuddyCopy.Onboarding.retry) {
                        retryPairing()
                    }
                    .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
                    Button(BuddyCopy.Onboarding.backToList) {
                        cleanupAbandonedPairing()
                        startScanning()
                    }
                    .buttonStyle(.plain)
                }
            } else if selectedDeviceUUID != nil {
                ProgressView()
                    .tint(BuddyTheme.amberInk)
                Text(BuddyCopy.Onboarding.connecting)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.ink)
                Text(BuddyCopy.Onboarding.pairingHelp)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.inkFaint)
                    .multilineTextAlignment(.center)
            } else {
                bleDeviceList
            }
        }
        .padding(14)
        .frame(width: 480)
        .frame(minHeight: 96)

    }

    private var bleDeviceList: some View {
        VStack(spacing: 8) {
            if scanner.bluetoothUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BuddyTheme.amberInk)
                Text(BuddyCopy.Onboarding.bluetoothOff)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.ink)
                Text(BuddyCopy.Onboarding.bluetoothOffHint)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.inkFaint)
            } else if scanner.devices.isEmpty {
                ProgressView()
                    .tint(BuddyTheme.amberInk)
                Text(BuddyCopy.Onboarding.scanning)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.inkSoft)
            } else {
                ForEach(scanner.devices, id: \.identifier) { device in
                    Button {
                        chooseDevice(device.identifier)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.body)
                                    .foregroundStyle(BuddyTheme.ink)
                                Text(String(device.identifier.uuidString.prefix(8)) + "…")
                                    .font(.body)
                                    .foregroundStyle(BuddyTheme.inkFaint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BuddyTheme.inkFaint)
                        }
                        .padding(10)

                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func navigationBar(nextTitle: String = BuddyCopy.shared.onboarding.next, nextDisabled: Bool = false) -> some View {
        HStack {
            Button(BuddyCopy.shared.onboarding.back) { model.goBack() }
                .buttonStyle(.plain)
            Spacer()
            Button(nextTitle) { model.advance() }
                .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.45 : 1)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func stepHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.largeTitle)
                .foregroundStyle(BuddyTheme.ink)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
        }
    }

    private func normalizeSelectedSpecies() {
        if model.selectedSpecies != Pet.defaultSpecies {
            model.selectedSpecies = Pet.defaultSpecies
        }
        engine.setSpecies(Pet.defaultSpecies)
    }

    private func startScanning() {
        guard !snapshotFrozen else { return }
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


}
