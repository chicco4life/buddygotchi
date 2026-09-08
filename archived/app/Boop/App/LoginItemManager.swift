import ServiceManagement

@MainActor
final class LoginItemManager {
    static let shared = LoginItemManager()

    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        default:
            return .unavailable
        }
    }

    var isEnabled: Bool {
        status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail — user can set this in System Settings
        }
    }
}
