import SwiftUI

enum BuddyOutputTarget: String, CaseIterable, Identifiable {
    case thisMac = "this-mac"
    case m5stack = "m5stack"
    case buddygotchiDevice = "buddygotchi-device"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisMac: return "This Mac"
        case .m5stack: return "M5Stack"
        case .buddygotchiDevice: return "Buddygotchi Device"
        }
    }

    var description: String {
        switch self {
        case .thisMac: return "Your buddy lives in the menu bar popover"
        case .m5stack: return "Your buddy lives on an M5Stack over Bluetooth"
        case .buddygotchiDevice: return "A dedicated hardware buddy over Bluetooth"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .thisMac, .m5stack: return true
        case .buddygotchiDevice: return false
        }
    }
}

struct SetupWizardView: View {
    let engine: BuddyEngine
    let onFinish: () -> Void

    @State private var step = 0
    @State private var navigatingForward = true
    @State private var selectedSpecies = "cat"
    @State private var selectedOutput: BuddyOutputTarget = .thisMac
    @State private var launchAtLogin = false
    @AppStorage("setupCompleted") private var setupCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var agentDetection: [AgentKind: Bool] = [:]
    @State private var agentInstalled: [AgentKind: Bool] = [:]
    @State private var connectionTestPassed = false

    @State private var bleManager: BLEManager?
    @State private var discoveredDevices: [BLEManager.DiscoveredPeripheral] = []
    @State private var selectedDeviceUUID: UUID?
    @State private var bleScanTask: Task<Void, Never>?

    private let species = buddyOrder

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.top, 16)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: agentStep
                case 2: testConnectionStep
                case 3: personalizeStep
                case 4: outputStep
                case 5: doneStep
                default: EmptyView()
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
            ))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.fullPanelHeight)
        .preferredColorScheme(.dark)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? BuddyTheme.accent : Color.white.opacity(0.1))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.3), value: step)
            }
        }
        .padding(.horizontal, 40)
        .accessibilityElement()
        .accessibilityLabel("Setup progress, step \(step + 1) of 6")
        .accessibilityValue("\(Int(Double(step + 1) / 6.0 * 100)) percent")
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            PetStageView(petState: .idle, species: "cat", fontSize: 20)

            Spacer().frame(height: 12)

            stepHeader(
                title: "meet your buddy",
                subtitle: "a coding companion that reacts to your AI agent"
            )

            Spacer()

            Button("Get Started") {
                navigatingForward = true
                step = 1
            }
            .buttonStyle(BuddyPrimaryButtonStyle())
        }
    }

    // MARK: - Step 1: Connect Agent

    private var agentStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "connect your agent",
                subtitle: "install hooks for at least one agent"
            )

            Spacer().frame(height: 16)

            VStack(spacing: 6) {
                ForEach(AgentKind.allCases) { agent in
                    agentRow(agent: agent)
                }
            }

            Spacer()

            wizardNavigation(
                onBack: { navigatingForward = false; step = 0 },
                onNext: { navigatingForward = true; step = 2 },
                nextDisabled: !agentInstalled.values.contains(true)
            )
        }
        .onAppear {
            agentDetection = HookInstaller.shared.detectInstalledAgents()
            for agent in AgentKind.allCases {
                agentInstalled[agent] = HookInstaller.shared.isInstalled(agent: agent)
            }
        }
    }

    // MARK: - Step 2: Test Connection

    private var testConnectionStep: some View {
        let isConnected = engine.state.desktop.status == .connected

        return VStack(spacing: 0) {
            stepHeader(
                title: "test your connection",
                subtitle: "open your agent and send any message"
            )

            Spacer().frame(height: 16)

            PetStageView(
                petState: connectionTestPassed ? .celebrate : .sleep,
                species: selectedSpecies
            )

            Spacer().frame(height: 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? BuddyTheme.connected : BuddyTheme.disconnected)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(isConnected ? "Connected" : "Waiting for connection...")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(isConnected ? .primary : .secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            HStack {
                Button("Back") { navigatingForward = false; step = 1 }
                    .buttonStyle(BuddySecondaryButtonStyle())
                Spacer()
                if connectionTestPassed {
                    Button("Next") { navigatingForward = true; step = 3 }
                        .buttonStyle(BuddyPrimaryButtonStyle())
                } else {
                    Button("Skip") { navigatingForward = true; step = 3 }
                        .buttonStyle(BuddySecondaryButtonStyle())
                }
            }
        }
        .onChange(of: engine.state.desktop.status) { _, newValue in
            if newValue == .connected && !connectionTestPassed {
                connectionTestPassed = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.0))
                    if step == 2 { navigatingForward = true; step = 3 }
                }
            }
        }
    }

    // MARK: - Step 3: Personalize

    private var personalizeStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: "choose your buddy")

            Spacer().frame(height: 20)

            HStack(spacing: 16) {
                Button(action: { cycleSpecies(-1) }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous species")

                VStack(spacing: 8) {
                    PetStageView(petState: .idle, species: selectedSpecies)

                    Text(selectedSpecies)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(selectedSpeciesColor)
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

            Spacer()

            wizardNavigation(
                onBack: { navigatingForward = false; step = 2 },
                onNext: { navigatingForward = true; step = 4 }
            )
        }
    }

    // MARK: - Step 4: Display Output

    private var outputStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "where should your buddy live?",
                subtitle: "you can add more displays later in Settings"
            )

            Spacer().frame(height: 16)

            VStack(spacing: 6) {
                ForEach(BuddyOutputTarget.allCases) { target in
                    outputRow(target: target)
                }
            }

            if selectedOutput == .m5stack {
                Spacer().frame(height: 12)
                bleScanContent
            }

            Spacer()

            wizardNavigation(
                onBack: { navigatingForward = false; step = 3 },
                onNext: {
                    if selectedOutput == .m5stack, let uuid = selectedDeviceUUID {
                        UserDefaults.standard.set(uuid.uuidString, forKey: "esp32PeripheralUUID")
                    }
                    stopBLEScan()
                    navigatingForward = true
                    step = 5
                },
                nextDisabled: selectedOutput == .m5stack && selectedDeviceUUID == nil
            )
        }
        .onChange(of: selectedOutput) { _, newValue in
            if newValue == .m5stack { startBLEScan() }
            else { stopBLEScan() }
        }
    }

    // MARK: - Step 5: Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            PetStageView(petState: .celebrate, species: selectedSpecies)

            Spacer().frame(height: 12)

            stepHeader(title: "your buddy is ready!")

            Spacer().frame(height: 16)

            VStack(alignment: .leading, spacing: 4) {
                let installed = AgentKind.allCases.filter { agentInstalled[$0] == true }
                Text("Agents: \(installed.map(\.displayName).joined(separator: ", "))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Display: \(selectedOutput.displayName)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buddyCard(elevated: true)
            .accessibilityElement(children: .combine)

            Spacer().frame(height: 16)

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .tint(BuddyTheme.accent)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.shared.setEnabled(newValue)
                }

            Spacer()

            VStack(spacing: 6) {
                Button("Done") {
                    UserDefaults.standard.set(selectedSpecies, forKey: "buddySpecies")
                    UserDefaults.standard.set(selectedOutput.rawValue, forKey: "buddyOutput")
                    setupCompleted = true
                    onFinish()
                }
                .buttonStyle(BuddyPrimaryButtonStyle())

                Text("Tip: click the menu bar icon anytime")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Shared Components

    private func stepHeader(title: String, subtitle: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func wizardNavigation(
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void,
        nextDisabled: Bool = false
    ) -> some View {
        HStack {
            Button("Back", action: onBack)
                .buttonStyle(BuddySecondaryButtonStyle())
            Spacer()
            Button("Next", action: onNext)
                .buttonStyle(BuddyPrimaryButtonStyle())
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.5 : 1.0)
        }
    }

    // MARK: - Row Builders

    private func agentRow(agent: AgentKind) -> some View {
        let detected = agentDetection[agent] ?? false
        let installed = agentInstalled[agent] ?? false

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName).font(.system(.callout, design: .rounded))
                Text(detected ? "Detected" : "Not Detected")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(detected ? BuddyTheme.accent : .secondary)
            }
            Spacer()
            Button(installed ? "Installed" : "Install Hooks") {
                if HookInstaller.shared.install(agent: agent) {
                    agentInstalled[agent] = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(BuddyTheme.accent)
            .disabled(installed)
        }
        .buddyCard()
        .accessibilityElement(children: .combine)
    }

    private func outputRow(target: BuddyOutputTarget) -> some View {
        Button {
            if target.isAvailable { selectedOutput = target }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(target.displayName).font(.system(.callout, design: .rounded))
                        if !target.isAvailable {
                            Text("Coming Soon")
                                .font(.system(.caption2, design: .rounded))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                        if target == .thisMac {
                            Text("Default")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(BuddyTheme.accent)
                        }
                    }
                    Text(target.description)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if target.isAvailable {
                    Image(systemName: selectedOutput == target ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedOutput == target ? BuddyTheme.accent : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .buddyCard()
        .opacity(target.isAvailable ? 1.0 : 0.5)
        .disabled(!target.isAvailable)
        .accessibilityLabel("\(target.displayName), \(target.description)")
        .accessibilityAddTraits(selectedOutput == target ? .isSelected : [])
    }

    private func cycleSpecies(_ direction: Int) {
        guard let idx = species.firstIndex(of: selectedSpecies) else { return }
        let next = (idx + direction + species.count) % species.count
        selectedSpecies = species[next]
    }

    private var selectedSpeciesColor: Color {
        buddySpeciesColor(for: selectedSpecies)
    }

    // MARK: - BLE Scan

    private var bleScanContent: some View {
        VStack(spacing: 6) {
            if discoveredDevices.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(BuddyTheme.accent)
                    Text("Scanning for devices...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else {
                ForEach(discoveredDevices, id: \.identifier) { device in
                    Button {
                        selectedDeviceUUID = device.identifier
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.system(.callout, design: .rounded))
                                Text(device.identifier.uuidString.prefix(8) + "...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedDeviceUUID == device.identifier
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedDeviceUUID == device.identifier ? BuddyTheme.accent : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .buddyCard()
                    .accessibilityLabel(device.name)
                    .accessibilityAddTraits(selectedDeviceUUID == device.identifier ? .isSelected : [])
                }
            }
        }
    }

    private func startBLEScan() {
        stopBLEScan()
        let manager = BLEManager()
        bleManager = manager
        discoveredDevices = []
        selectedDeviceUUID = nil
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
        bleScanTask?.cancel()
        bleScanTask = nil
        bleManager?.stopScan()
        bleManager = nil
    }
}
