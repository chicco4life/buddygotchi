import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var engine: BuddyEngine?
    private var defaultAction: (() -> Void)?
    private var available = false
    private let passiveCategoryId = "TOOL_CALL"
    private let approvalCategoryId = "TOOL_CALL_APPROVAL"

    func setup(engine: BuddyEngine, defaultAction: (() -> Void)? = nil) {
        self.engine = engine
        self.defaultAction = defaultAction

        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        available = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let approve = UNNotificationAction(
            identifier: "APPROVE",
            title: BuddyCopy.approve,
            options: [.authenticationRequired]
        )
        let deny = UNNotificationAction(
            identifier: "DENY",
            title: BuddyCopy.deny,
            options: [.destructive]
        )
        let passiveCategory = UNNotificationCategory(
            identifier: passiveCategoryId,
            actions: [],
            intentIdentifiers: []
        )
        let approvalCategory = UNNotificationCategory(
            identifier: approvalCategoryId,
            actions: [approve, deny],
            intentIdentifiers: []
        )
        center.setNotificationCategories([passiveCategory, approvalCategory])
    }

    func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postToolNotification(prompt: Prompt) {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self?.deliverToolNotification(prompt: prompt) }
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        UserDefaults.standard.set(true, forKey: DefaultsKey.notificationPermissionRequested)
                        Task { @MainActor in self?.deliverToolNotification(prompt: prompt) }
                    }
                }
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
        content.categoryIdentifier = prompt.isApproval ? approvalCategoryId : passiveCategoryId
        content.sound = .default

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
        completionHandler([.banner, .sound])
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
            case "APPROVE":
                self.engine?.resolveApproval(requestId: requestId, decision: .allow)
            case "DENY":
                self.engine?.resolveApproval(requestId: requestId, decision: .deny)
            default:
                self.defaultAction?()
            }
        }
        completionHandler()
    }
}
