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
    case firstContact
    case display
    case done
}

@Observable
@MainActor
final class OnboardingModel {
    var step: OnboardingStep {
        didSet {
            UserDefaults.standard.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
        }
    }

    var selectedSpecies: String {
        didSet {
            UserDefaults.standard.set(selectedSpecies, forKey: DefaultsKey.buddySpecies)
        }
    }

    var buddyName: String {
        didSet {
            UserDefaults.standard.set(buddyName, forKey: DefaultsKey.buddyName)
        }
    }

    var selectedOutput: BuddyOutputTarget {
        didSet {
            UserDefaults.standard.set(selectedOutput.rawValue, forKey: DefaultsKey.buddyOutput)
        }
    }

    var launchAtLogin: Bool
    var notificationRequested: Bool
    var agentDetection: [AgentKind: Bool] = [:]
    var agentInstalled: [AgentKind: Bool] = [:]
    var agentErrors: [AgentKind: String] = [:]
    var heardFromAgent: AgentKind?
    var firstContactStartedAt = Date.now
    var showingTroubleshooting = false
    var pairingTimedOut = false

    init() {
        let rawStep = UserDefaults.standard.integer(forKey: DefaultsKey.onboardingStep)
        step = OnboardingStep(rawValue: rawStep) ?? .welcome

        let storedSpecies = UserDefaults.standard.string(forKey: DefaultsKey.buddySpecies)
        selectedSpecies = storedSpecies.flatMap { buddyOrder.contains($0) ? $0 : nil } ?? Pet.defaultSpecies

        buddyName = UserDefaults.standard.string(forKey: DefaultsKey.buddyName) ?? ""

        let outputRaw = UserDefaults.standard.string(forKey: DefaultsKey.buddyOutput) ?? BuddyOutputTarget.thisMac.rawValue
        selectedOutput = BuddyOutputTarget(rawValue: outputRaw) ?? .thisMac

        if Bundle.main.bundlePath.hasSuffix(".app") {
            launchAtLogin = LoginItemManager.shared.isEnabled
        } else {
            launchAtLogin = true
        }
        notificationRequested = UserDefaults.standard.bool(forKey: DefaultsKey.notificationPermissionRequested)
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
        if next == .firstContact {
            firstContactStartedAt = .now
            showingTroubleshooting = false
        }
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: max(step.rawValue - 1, 0)) else { return }
        step = previous
    }

    func complete() {
        UserDefaults.standard.set(selectedSpecies, forKey: DefaultsKey.buddySpecies)
        UserDefaults.standard.set(selectedOutput.rawValue, forKey: DefaultsKey.buddyOutput)
        UserDefaults.standard.set(buddyName, forKey: DefaultsKey.buddyName)
        if isPackagedApp {
            LoginItemManager.shared.setEnabled(launchAtLogin)
        }
        UserDefaults.standard.set(true, forKey: DefaultsKey.setupCompleted)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.onboardingStep)
    }
}
