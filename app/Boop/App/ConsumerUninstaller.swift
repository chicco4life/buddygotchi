import Foundation
import UserNotifications

@MainActor
enum ConsumerUninstaller {
    static func removeInstalledState() throws {
        var failedUninstalls: [String] = []
        for agent in AgentKind.allCases {
            let outcome = HookInstaller.shared.uninstall(agent: agent)
            if case .failed(let reason) = outcome {
                failedUninstalls.append("\(agent.displayName): \(reason)")
            }
        }

        LoginItemManager.shared.setEnabled(false)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let stateURL = URL(fileURLWithPath: BuddyConfig.default.stateDir, isDirectory: true)
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
        }

        let defaults = UserDefaults.standard
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        } else {
            defaults.removeObject(forKey: DefaultsKey.approvalMode)
            defaults.removeObject(forKey: DefaultsKey.buddyName)
            defaults.removeObject(forKey: DefaultsKey.buddyOutput)
            defaults.removeObject(forKey: DefaultsKey.buddySpecies)
            defaults.removeObject(forKey: DefaultsKey.esp32PeripheralUUID)
            defaults.removeObject(forKey: DefaultsKey.firmwareManifestCache)
            defaults.removeObject(forKey: DefaultsKey.interactiveMode)
            defaults.removeObject(forKey: DefaultsKey.installedAgents)
            defaults.removeObject(forKey: DefaultsKey.notificationPermissionRequested)
            defaults.removeObject(forKey: DefaultsKey.onboardingStep)
            defaults.removeObject(forKey: DefaultsKey.showMenuHint)
            defaults.removeObject(forKey: DefaultsKey.soundsEnabled)
            defaults.removeObject(forKey: DefaultsKey.setupCompleted)
        }
        defaults.synchronize()

        if !failedUninstalls.isEmpty {
            throw ConsumerUninstallError.leftoverHookFiles(failedUninstalls)
        }
    }
}

enum ConsumerUninstallError: LocalizedError {
    case leftoverHookFiles([String])

    var errorDescription: String? {
        switch self {
        case .leftoverHookFiles(let failures):
            return """
                Boop was removed, but some agent hook files still need manual cleanup:
                \(failures.joined(separator: "\n"))
                """
        }
    }
}
