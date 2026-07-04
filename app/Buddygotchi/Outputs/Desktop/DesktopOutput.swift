import AppKit
import Foundation

@MainActor
protocol PopoverPresenting: AnyObject {
    var isPopoverShown: Bool { get }
    var isInteractiveModeEnabled: Bool { get }
    func showPopover(isApproval: Bool, dismissAfter seconds: TimeInterval)
    func closePopover()
    func cancelPopoverAutoDismiss()
}

@MainActor
protocol DesktopNotificationPosting: AnyObject {
    func postToolNotification(prompt: Prompt)
    func clearNotification(promptId: String)
}

extension NotificationManager: DesktopNotificationPosting {}

@MainActor
final class DesktopOutput: OutputProvider {
    let id = "desktop"

    private weak var statusItem: NSStatusItem?
    private weak var presenter: (any PopoverPresenting)?
    private let notifier: any DesktopNotificationPosting
    private let playCelebrate: () -> Void
    private let playAttention: () -> Void
    private let playError: () -> Void

    private var lastIconKey: String?

    init(
        statusItem: NSStatusItem,
        presenter: any PopoverPresenting,
        notifier: any DesktopNotificationPosting = NotificationManager.shared,
        playCelebrate: @escaping () -> Void = { NSSound(named: "Funk")?.play() },
        playAttention: @escaping () -> Void = { NSSound(named: "Glass")?.play() },
        playError: @escaping () -> Void = { NSSound(named: "Sosumi")?.play() }
    ) {
        self.statusItem = statusItem
        self.presenter = presenter
        self.notifier = notifier
        self.playCelebrate = playCelebrate
        self.playAttention = playAttention
        self.playError = playError
    }

    func start(engine: BuddyEngine) async {}
    func stop() async {}

    func stateDidChange(prev: BuddyState, next: BuddyState) {
        updateIcon(next)
        let notificationPosted = updateNotifications(prev: prev, next: next)
        playTransitionSounds(prev: prev, next: next, notificationPosted: notificationPosted)
        updateInteractiveMode(prev: prev, next: next)
    }

    private func updateIcon(_ state: BuddyState) {
        let iconKey = state.pet.state.rawValue
        guard iconKey != lastIconKey else { return }
        lastIconKey = iconKey
        statusItem?.button?.image = Self.statusIcon(for: state.pet.state)
    }

    static func statusIcon(for state: PetState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let badgeColor = badgeColor(for: state)
        let image = NSImage(size: size, flipped: false) { rect in
            let bodyRect = NSRect(x: rect.minX + 2.4, y: rect.minY + 4.2, width: 13.2, height: 9.6)
            let body = NSBezierPath(ovalIn: bodyRect)
            NSColor.labelColor.setFill()
            body.fill()

            NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
            switch state {
            case .sleep:
                NSBezierPath(roundedRect: NSRect(x: 6.0, y: 8.6, width: 2.4, height: 0.9), xRadius: 0.5, yRadius: 0.5).fill()
                NSBezierPath(roundedRect: NSRect(x: 9.8, y: 8.6, width: 2.4, height: 0.9), xRadius: 0.5, yRadius: 0.5).fill()
            default:
                NSBezierPath(ovalIn: NSRect(x: 6.4, y: 8.3, width: 1.7, height: 2.6)).fill()
                NSBezierPath(ovalIn: NSRect(x: 10.0, y: 8.3, width: 1.7, height: 2.6)).fill()
            }

            if let badgeColor {
                badgeColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.8, y: 2.2, width: 4.0, height: 4.0)).fill()
            }
            return true
        }
        image.accessibilityDescription = accessibilityDescription(for: state)
        return image
    }

    private static func badgeColor(for state: PetState) -> NSColor? {
        switch state {
        case .attention:
            return NSColor(srgbRed: 0.91, green: 0.64, blue: 0.24, alpha: 1)
        case .celebrate:
            return NSColor(srgbRed: 0.50, green: 0.66, blue: 0.42, alpha: 1)
        case .error:
            return NSColor(srgbRed: 0.79, green: 0.42, blue: 0.37, alpha: 1)
        default:
            return nil
        }
    }

    private static func accessibilityDescription(for state: PetState) -> String {
        switch state {
        case .attention: return "Buddygotchi — needs you"
        case .celebrate: return "Buddygotchi — finished"
        case .error: return "Buddygotchi — stuck"
        case .busy: return "Buddygotchi — working"
        case .thinking: return "Buddygotchi — thinking"
        case .idle: return "Buddygotchi — idle"
        case .sleep: return "Buddygotchi — asleep"
        }
    }

    private func updateNotifications(prev: BuddyState, next: BuddyState) -> Bool {
        let previousPromptId = prev.prompt?.id
        let nextPrompt = next.prompt
        var posted = false

        if let previousPromptId, previousPromptId != nextPrompt?.id {
            notifier.clearNotification(promptId: previousPromptId)
        }

        guard let nextPrompt, nextPrompt.id != previousPromptId else { return false }
        if presenter?.isPopoverShown != true {
            notifier.postToolNotification(prompt: nextPrompt)
            posted = true
        }
        return posted
    }

    private func playTransitionSounds(prev: BuddyState, next: BuddyState, notificationPosted: Bool) {
        let soundsEnabled = UserDefaults.standard.object(forKey: DefaultsKey.soundsEnabled) as? Bool ?? true
        guard soundsEnabled, !notificationPosted else { return }
        guard prev.pet.state != next.pet.state else { return }
        if next.pet.state == .celebrate && (next.lastTaskDurationMs ?? 0) >= 30_000 {
            playCelebrate()
        } else if next.pet.state == .attention {
            playAttention()
        } else if next.pet.state == .error {
            playError()
        }
    }

    private func updateInteractiveMode(prev: BuddyState, next: BuddyState) {
        guard let presenter else { return }
        guard presenter.isInteractiveModeEnabled else {
            presenter.cancelPopoverAutoDismiss()
            return
        }
        guard prev.pet.state != next.pet.state else { return }

        if next.pet.state == .celebrate
            && (next.lastTaskDurationMs ?? 0) >= 30_000
            && !presenter.isPopoverShown
        {
            presenter.showPopover(isApproval: next.prompt?.isApproval == true, dismissAfter: 3.0)
        } else if next.pet.state == .attention && !presenter.isPopoverShown {
            presenter.showPopover(isApproval: next.prompt?.isApproval == true, dismissAfter: 15.0)
        } else if (next.pet.state == .idle || next.pet.state == .sleep) && presenter.isPopoverShown {
            presenter.cancelPopoverAutoDismiss()
            presenter.closePopover()
        }
    }
}
