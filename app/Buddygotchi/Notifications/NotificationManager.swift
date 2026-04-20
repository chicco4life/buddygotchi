import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var engine: BuddyEngine?
    private var available = false
    private let categoryId = "TOOL_CALL"

    func setup(engine: BuddyEngine) {
        self.engine = engine

        guard Bundle.main.bundleIdentifier != nil else {
            return
        }

        available = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postToolNotification(prompt: Prompt) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = prompt.tool
        content.body = prompt.hint
        content.categoryIdentifier = categoryId
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
}
