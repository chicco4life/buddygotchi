import Foundation
import UserNotifications

@MainActor
enum ConsumerUninstaller {
    static func removeInstalledState() throws {
        for agent in AgentKind.allCases {
            HookInstaller.shared.uninstall(agent: agent)
        }

        LoginItemManager.shared.setEnabled(false)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let stateURL = URL(fileURLWithPath: BuddyConfig.default.stateDir, isDirectory: true)
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
        }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.approvalMode)
        defaults.removeObject(forKey: DefaultsKey.esp32PeripheralUUID)
        defaults.removeObject(forKey: DefaultsKey.firmwareManifestCache)
        defaults.synchronize()
    }
}
