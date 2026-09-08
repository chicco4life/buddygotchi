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
    @State private var didAutoConnect = false
    @State private var waking = false
    @State private var wakeStarted = Date.now
    @State private var copiedPrompt = false
    @State private var copiedPromptResetTask: Task<Void, Never>?
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
            BuddyTheme.paper.ignoresSafeArea()

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
            copiedPromptResetTask?.cancel()
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

            TimelineView(.animation(minimumInterval: 0.1, paused: !waking)) { timeline in
                CreatureView(creature: wakeCreature(elapsed: timeline.date.timeIntervalSince(wakeStarted)), grey: true, wakeProgress: waking ? timeline.date.timeIntervalSince(wakeStarted) : 0)
                    .frame(width: 260, height: 200)
            }

            Spacer()

            Button(BuddyCopy.phase7("continue")) {
                if waking { model.advance(); return }
                waking = true; wakeStarted = .now
                Task {
                    try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 5))
                    if model.step == .welcome { model.advance() }
                }
            }
            .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
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
            CreatureView(creature: engine.state.creature, grey: model.heardAgents.isEmpty)
                .frame(width: 150, height: 100)


            VStack(spacing: 10) {
                ForEach(AgentKind.allCases) { agent in
                    VStack(alignment: .leading, spacing: 4) {
                        agentRow(agent)
                        if model.heardAgents.contains(agent) { Text(BuddyCopy.heardFrom(agent.displayName)).font(.buddy(11)).foregroundStyle(BuddyTheme.greenInk) }
                    }
                }
            }
            .frame(width: 520)

            Spacer()

            HStack {
                HStack(spacing: 12) {
                    Button(BuddyCopy.shared.onboarding.back) { model.goBack() }
                        .buttonStyle(BuddySecondaryButtonStyle(size: .large))

                    Button(BuddyCopy.Onboarding.skipForNow) {
                        model.advance()
                    }
                    .buttonStyle(BuddySecondaryButtonStyle(size: .large))
                }

                Spacer()

                Button(BuddyCopy.shared.onboarding.next) { model.advance() }
                    .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
                    .disabled(!model.canFinishAgents)
                    .opacity(model.canFinishAgents ? 1 : 0.45)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .task {
            guard !snapshotFrozen else { return }
            while !Task.isCancelled {
                model.observe(engine.diagnosticLog.entries)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            guard !snapshotFrozen else { return }
            model.refreshAgents()
        }
    }


    private func wakeCreature(elapsed: Double) -> Creature {
        var creature = Creature.initial
        if waking && elapsed > 1 { creature.state = .idle }
        if waking && elapsed > 3 { creature.overlay = .greet; creature.greetLevel = 1 }
        return creature
    }

    private var firstContactStep: some View {
        VStack(spacing: 24) {
            Spacer()
            CreatureView(creature: engine.state.creature, grey: model.heardAgents.isEmpty).frame(width: 240, height: 180)
            stepHeader(title: BuddyCopy.phase7("name"), subtitle: BuddyCopy.phase7("namePermanent"))
            TextField(BuddyCopy.Onboarding.namePlaceholder, text: Binding(get: { model.buddyName }, set: { model.buddyName = $0.prefix(utf8Bytes: 23) }))
                .textFieldStyle(.roundedBorder).frame(width: 320).disabled(model.nameIsLocked)
            Spacer()
            Button(BuddyCopy.phase7("continue")) { if model.saveName() { esp32Output.refreshSnapshot(); model.advance() } }
                .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
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
                    .font(.buddy(11))
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

    private var firstCheer: Creature {
        if engine.state.creature.state == .done { return engine.state.creature }
        var creature = Creature.initial
        creature.state = .done; creature.cheer = .hop; creature.gift = true
        creature.giftLine = BuddyCopy.phase7("firstOne")
        return creature
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            CreatureView(creature: firstCheer, grey: model.heardAgents.isEmpty).frame(width: 240, height: 180)
            Text(BuddyCopy.phase7("firstOne")).font(.buddy(18, weight: .semibold))

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuddyCopy.Onboarding.launchAtLogin)
                            .font(.buddy(13, weight: .semibold))
                            .foregroundStyle(BuddyTheme.ink)
                        Text(model.isPackagedApp ? BuddyCopy.Onboarding.launchAtLoginDescription : BuddyCopy.Onboarding.launchAtLoginUnavailable)
                            .font(.buddy(11))
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
                        .toggleStyle(BuddySwitchToggleStyle())
                        .tint(BuddyTheme.amberInk)
                        .disabled(!model.isPackagedApp)
                }
                .tint(BuddyTheme.amberInk)

                BuddyDivider()

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BuddyCopy.Onboarding.notificationsTitle)
                            .font(.buddy(13, weight: .semibold))
                            .foregroundStyle(BuddyTheme.ink)
                        Text(BuddyCopy.Onboarding.notificationsDescription)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.inkFaint)
                    }
                    Spacer()
                    if model.notificationRequested {
                        Button(BuddyCopy.Onboarding.notificationsEnabled) {}
                            .buttonStyle(BuddySecondaryButtonStyle(size: .large))
                            .disabled(true)
                    } else {
                        Button(BuddyCopy.Onboarding.enableNotifications) {
                            NotificationManager.shared.requestPermission()
                            UserDefaults.standard.set(true, forKey: DefaultsKey.notificationPermissionRequested)
                            model.notificationRequested = true
                        }
                        .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
                    }
                }
            }
            .padding(16)
            .frame(width: 520)
            .buddySurface()

            Spacer()

            HStack {
                Button(BuddyCopy.shared.onboarding.back) { model.goBack() }
                    .buttonStyle(BuddySecondaryButtonStyle(size: .large))
                Spacer()
                Button(BuddyCopy.Onboarding.startWatching) {
                    model.complete()
                    engine.setSpecies(model.selectedSpecies)
                    onFinish()
                }
                .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
                .keyboardShortcut(.return, modifiers: [])
            }
        }.onAppear { if !snapshotFrozen { engine.firstCheer() } }
    }

    /// The first-contact step used to watch a sleeping pet wake up. The creature
    /// belongs to the device now, so the step reports the same thing in the
    /// abstract: listening, then heard. The heading carries the words.
    private var listeningIndicator: some View {
        let heard = model.heardFromAgent != nil
        return Image(systemName: heard ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(heard ? BuddyTheme.green : BuddyTheme.inkFaint)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .buddyEase(0.35), value: heard)
            .accessibilityHidden(true)
    }

    private var adoptionCard: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text(BuddyCopy.Onboarding.doneTitle)
                    .font(.buddy(22, weight: .semibold))
                    .foregroundStyle(BuddyTheme.ink)
                Text(model.displayName)
                    .font(.buddy(34, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amberInk)

                chipRow(title: BuddyCopy.shared.onboarding.agents, value: model.installedAgents.isEmpty ? BuddyCopy.shared.onboarding.skipped : model.installedAgents.map(\.displayName).joined(separator: ", "))
                chipRow(title: BuddyCopy.shared.onboarding.display, value: model.selectedOutput.displayName)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 560)
        .buddySurface()
    }

    private func chipRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.buddy(9.5, weight: .semibold))
                .foregroundStyle(BuddyTheme.inkFaint)
                .frame(width: 64, alignment: .trailing)
            Text(value)
                .font(.buddy(11, weight: .semibold))
                .foregroundStyle(BuddyTheme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    .font(.buddy(13, weight: .semibold))
                    .foregroundStyle(BuddyTheme.ink)
                Text(error ?? (detected ? BuddyCopy.Onboarding.detected : BuddyCopy.Onboarding.notDetectedHint))
                    .font(.buddy(11))
                    .foregroundStyle(error == nil ? BuddyTheme.inkFaint : BuddyTheme.clay)
            }

            Spacer()

            if installed {
                Button(BuddyCopy.Onboarding.connected) {}
                    .buttonStyle(BuddySecondaryButtonStyle(size: .large))
                    .disabled(true)
            } else {
                Button(BuddyCopy.Onboarding.connect) {
                    model.connect(agent: agent, diagnosticLog: engine.diagnosticLog)
                }
                .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
            }
        }
        .padding(14)
        .buddySurface()
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
                        .font(.buddy(13, weight: .semibold))
                        .foregroundStyle(BuddyTheme.ink)
                    Text(target.description)
                        .font(.buddy(11))
                        .foregroundStyle(BuddyTheme.inkFaint)
                }
                Spacer()
            }
            .padding(14)
            .buddySurface()
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BuddyTheme.ink)
            }
        }
        .frame(width: 20, height: 20)
    }

    private var blePairingPanel: some View {
        VStack(spacing: 10) {
            if esp32Output.connectionState == .connected && selectedDeviceUUID != nil {
                Label(BuddyCopy.Onboarding.connectedCheered, systemImage: "checkmark.circle.fill")
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.greenInk)
            } else if model.pairingTimedOut {
                Text(BuddyCopy.Onboarding.pairingTimeout)
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.clayInk)
                HStack {
                    Button(BuddyCopy.Onboarding.retry) {
                        retryPairing()
                    }
                    .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
                    Button(BuddyCopy.Onboarding.backToList) {
                        cleanupAbandonedPairing()
                        startScanning()
                    }
                    .buttonStyle(BuddySecondaryButtonStyle(size: .large))
                }
            } else if selectedDeviceUUID != nil {
                ProgressView()
                    .tint(BuddyTheme.amberInk)
                Text(BuddyCopy.Onboarding.connecting)
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.ink)
                Text(BuddyCopy.Onboarding.pairingHelp)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkFaint)
                    .multilineTextAlignment(.center)
            } else {
                bleDeviceList
            }
        }
        .padding(14)
        .frame(width: 480)
        .frame(minHeight: 96)
        .buddySurface(BuddyTheme.paperSunken)
    }

    private var bleDeviceList: some View {
        VStack(spacing: 8) {
            if scanner.bluetoothUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BuddyTheme.amberInk)
                Text(BuddyCopy.Onboarding.bluetoothOff)
                    .font(.buddy(11, weight: .semibold))
                    .foregroundStyle(BuddyTheme.ink)
                Text(BuddyCopy.Onboarding.bluetoothOffHint)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkFaint)
            } else if scanner.devices.isEmpty {
                ProgressView()
                    .tint(BuddyTheme.amberInk)
                Text(BuddyCopy.Onboarding.scanning)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkSoft)
            } else {
                ForEach(scanner.devices, id: \.identifier) { device in
                    Button {
                        chooseDevice(device.identifier)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.buddy(11, weight: .semibold))
                                    .foregroundStyle(BuddyTheme.ink)
                                Text(String(device.identifier.uuidString.prefix(8)) + "…")
                                    .font(.buddy(11))
                                    .foregroundStyle(BuddyTheme.inkFaint)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(BuddyTheme.inkFaint)
                        }
                        .padding(10)
                        .buddySurface(radius: BuddyTheme.wellCornerRadius)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func navigationBar(nextTitle: String = BuddyCopy.shared.onboarding.next, nextDisabled: Bool = false) -> some View {
        HStack {
            Button(BuddyCopy.shared.onboarding.back) { model.goBack() }
                .buttonStyle(BuddySecondaryButtonStyle(size: .large))
            Spacer()
            Button(nextTitle) { model.advance() }
                .buttonStyle(BuddyPrimaryButtonStyle(size: .large))
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.45 : 1)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func stepHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.buddy(34, weight: .semibold))
                .foregroundStyle(BuddyTheme.ink)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.buddy(13))
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

    private func copyTestPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BuddyCopy.Onboarding.testPrompt, forType: .string)
        copiedPrompt = true
        copiedPromptResetTask?.cancel()
        copiedPromptResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiedPrompt = false
        }
    }
}
