import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var engine: BuddyEngine?
    private var defaultAction: (() -> Void)?
    private var available = false
    private let passiveCategoryId = "TOOL_CALL"

    func setup(engine: BuddyEngine, defaultAction: (() -> Void)? = nil) {
        self.engine = engine
        self.defaultAction = defaultAction

        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        available = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let passiveCategory = UNNotificationCategory(
            identifier: passiveCategoryId,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([passiveCategory])
    }

    func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postToolNotification(prompt: Prompt) {
        guard available, UserDefaults.standard.bool(forKey: DefaultsKey.notificationPermissionRequested) else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self?.deliverToolNotification(prompt: prompt) }
            case .notDetermined: return
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    private func deliverToolNotification(prompt: Prompt) {
        let content = UNMutableNotificationContent()
        let agentName = prompt.source.flatMap { AgentKind(rawValue: $0)?.displayName } ?? prompt.source ?? BuddyCopy.shared.common.appName
        content.title = BuddyCopy.notificationTitle(agentName: agentName)
        content.body = prompt.hint.isEmpty ? prompt.tool : "\(prompt.tool): \(prompt.hint)"
        content.categoryIdentifier = passiveCategoryId
        // Silent on purpose: Boop plays its own attention chirp for this same
        // prompt (ChirpDecision). Letting the banner ding too would either
        // double up or — as it did before — mask the chirp entirely behind the
        // generic system alert, so the pet never got to make its own noise.
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "tool-\(prompt.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func clearNotification(promptId: String) {
        guard available else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["tool-\(promptId)"]
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // No .sound — the chirp is ours to play. See deliverToolNotification.
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let requestId = identifier.hasPrefix("tool-") ? String(identifier.dropFirst(5)) : identifier
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor [requestId, actionIdentifier] in
            switch actionIdentifier {
            case "APPROVE", "DENY":
                // Retired actions on already-delivered notifications are inert.
                break
            default:
                self.defaultAction?()
            }
        }
        completionHandler()
    }
}
