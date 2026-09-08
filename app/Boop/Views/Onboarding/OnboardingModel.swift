import Foundation
import Observation

enum BuddyOutputTarget: String, CaseIterable, Identifiable {
    case thisMac = "this-mac"
    // "m5stack" is a legacy raw value and is deliberately frozen. It is persisted
    // in UserDefaults and never rendered — displayName returns "Hardware buddy" —
    // so renaming it buys no neutrality and would silently reset every paired
    // user to This Mac, because nothing else reads the preference at runtime.
    case hardware = "m5stack"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisMac: BuddyCopy.Onboarding.thisMac
        case .hardware: BuddyCopy.Onboarding.hardware
        }
    }

    var description: String {
        switch self {
        case .thisMac: BuddyCopy.Onboarding.thisMacDescription
        case .hardware: BuddyCopy.Onboarding.hardwareDescription
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case agents
    case display
    case firstContact
    case done
}

@Observable
@MainActor
final class OnboardingModel {
    private let defaults: UserDefaults

    var step: OnboardingStep {
        didSet {
            defaults.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
        }
    }

    var selectedSpecies: String {
        didSet {
            defaults.set(selectedSpecies, forKey: DefaultsKey.buddySpecies)
        }
    }

    var buddyName: String
    private(set) var heardAgents: Set<AgentKind> = []
    var nameIsLocked: Bool { defaults.bool(forKey: DefaultsKey.buddyNameLocked) || (defaults.bool(forKey: DefaultsKey.setupCompleted) && !(defaults.string(forKey: DefaultsKey.buddyName) ?? "").isEmpty) }
    func saveName() -> Bool {
        let name = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if !nameIsLocked { defaults.set(name.prefix(utf8Bytes: 23), forKey: DefaultsKey.buddyName); defaults.set(true, forKey: DefaultsKey.buddyNameLocked) }
        buddyName = defaults.string(forKey: DefaultsKey.buddyName) ?? name
        return true
    }
    func observe(_ entries: [DiagnosticEntry]) {
        for entry in entries where entry.category == "hook" {
            if let agent = AgentKind(rawValue: entry.source) { heardAgents.insert(agent); heardFromAgent = agent }
        }
    }

    private var lastScannedIndex = 0
    var heardEveryAgent: Bool { heardAgents.count == AgentKind.allCases.count }
    func observe(_ log: DiagnosticLog) {
        guard !heardEveryAgent else { return }
        let count = log.appendedCount
        let remaining = max(0, count - lastScannedIndex)
        observe(Array(log.entries.suffix(remaining)))
        lastScannedIndex = count
    }
    private(set) var wakeCreature = Creature.initial
    private(set) var waking = false
    func firstWake(reduceMotion: Bool) async {
        guard !waking else { return }
        waking = true
        defer { waking = false }
        do {
            try await Task.sleep(for: .seconds(reduceMotion ? 0 : 1))
            wakeCreature.state = .idle
            try await Task.sleep(for: .seconds(reduceMotion ? 0 : 2))
            wakeCreature.overlay = .greet; wakeCreature.greetLevel = 1
            try await Task.sleep(for: .seconds(reduceMotion ? 0 : 2))
            if step == .welcome { advance() }
        } catch { wakeCreature = .initial }
    }

    var selectedOutput: BuddyOutputTarget {
        didSet {
            defaults.set(selectedOutput.rawValue, forKey: DefaultsKey.buddyOutput)
        }
    }

    var launchAtLogin: Bool
    var notificationRequested: Bool
    var agentDetection: [AgentKind: Bool] = [:]
    var agentInstalled: [AgentKind: Bool] = [:]
    var agentErrors: [AgentKind: String] = [:]
    var heardFromAgent: AgentKind?
    var pairingTimedOut = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawStep = defaults.integer(forKey: DefaultsKey.onboardingStep)
        step = OnboardingStep(rawValue: rawStep) ?? .welcome

        let storedSpecies = defaults.string(forKey: DefaultsKey.buddySpecies)
        selectedSpecies = storedSpecies.flatMap { buddyOrder.contains($0) ? $0 : nil } ?? Pet.defaultSpecies

        buddyName = defaults.string(forKey: DefaultsKey.buddyName) ?? ""

        let outputRaw = defaults.string(forKey: DefaultsKey.buddyOutput) ?? BuddyOutputTarget.thisMac.rawValue
        selectedOutput = BuddyOutputTarget(rawValue: outputRaw) ?? .thisMac

        if Bundle.main.bundlePath.hasSuffix(".app") {
            launchAtLogin = LoginItemManager.shared.isEnabled
        } else {
            launchAtLogin = true
        }
        notificationRequested = defaults.bool(forKey: DefaultsKey.notificationPermissionRequested)
    }

    var canFinishAgents: Bool {
        agentInstalled.values.contains(true)
    }

    var installedAgents: [AgentKind] {
        AgentKind.allCases.filter { agentInstalled[$0] == true }
    }

    var displayName: String {
        let trimmed = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? selectedSpecies.capitalized : trimmed
    }

    var isPackagedApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    func refreshAgents() {
        agentDetection = HookInstaller.shared.detectInstalledAgents()
        for agent in AgentKind.allCases {
            agentInstalled[agent] = HookInstaller.shared.isInstalled(agent: agent)
        }
    }

    func connect(agent: AgentKind, diagnosticLog: DiagnosticLog) {
        agentErrors[agent] = nil
        if HookInstaller.shared.install(agent: agent) {
            agentInstalled[agent] = true
            diagnosticLog.log(
                category: "hooks",
                source: agent.rawValue,
                event: "onboardingInstall",
                detail: "connected from onboarding"
            )
        } else {
            let detail = BuddyCopy.Onboarding.hookInstallFailed
            agentErrors[agent] = detail
            diagnosticLog.log(
                category: "hooks",
                source: agent.rawValue,
                event: "onboardingInstallFailed",
                detail: detail
            )
        }
    }

    func advance() {
        guard let next = OnboardingStep(rawValue: min(step.rawValue + 1, OnboardingStep.allCases.count - 1)) else { return }
        step = next
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: max(step.rawValue - 1, 0)) else { return }
        step = previous
    }

    func complete() {
        defaults.set(selectedSpecies, forKey: DefaultsKey.buddySpecies)
        defaults.set(selectedOutput.rawValue, forKey: DefaultsKey.buddyOutput)
        _ = saveName()
        if isPackagedApp {
            LoginItemManager.shared.setEnabled(launchAtLogin)
        }
        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        defaults.removeObject(forKey: DefaultsKey.onboardingStep)
    }
}
