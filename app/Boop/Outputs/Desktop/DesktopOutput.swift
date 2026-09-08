import AppKit
import Foundation
import SwiftUI

/// Allows verification of the menu bar projection without creating a status item.
@MainActor
protocol StatusItemPresenting: AnyObject, Sendable {
    var image: NSImage? { get set }
    var toolTip: String? { get set }
}

extension NSStatusItem: StatusItemPresenting {
    var image: NSImage? {
        get { button?.image }
        set { button?.image = newValue }
    }
    var toolTip: String? {
        get { button?.toolTip }
        set { button?.toolTip = newValue }
    }
}

@MainActor
protocol PopoverPresenting: AnyObject {
    var isPopoverShown: Bool { get }
    var isInteractiveModeEnabled: Bool { get }
    func showPopover(dismissAfter seconds: TimeInterval)
    func closePopover()
    func cancelPopoverAutoDismiss()
}

extension PopoverPresenting {
    func showPopover(dismissAfter seconds: TimeInterval) {}
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

    private weak var statusItem: (any StatusItemPresenting)?
    private weak var presenter: (any PopoverPresenting)?
    private let notifier: any DesktopNotificationPosting
    private let soundsEnabled: () -> Bool
    private let playCelebrate: () -> Void
    private let playAttention: () -> Void
    private let playError: () -> Void

    init(
        statusItem: (any StatusItemPresenting)?,
        presenter: any PopoverPresenting,
        notifier: any DesktopNotificationPosting = NotificationManager.shared,
        soundsEnabled: @escaping () -> Bool = { SoundSettings.volume() > 0 },
        playCelebrate: @escaping () -> Void = { play("celebrate", fallback: "Funk") },
        playAttention: @escaping () -> Void = { play("attention", fallback: "Glass") },
        playError: @escaping () -> Void = { play("error", fallback: "Sosumi") }
    ) {
        self.statusItem = statusItem
        self.presenter = presenter
        self.notifier = notifier
        self.soundsEnabled = soundsEnabled
        self.playCelebrate = playCelebrate
        self.playAttention = playAttention
        self.playError = playError
    }

    private static func play(_ name: String, fallback: String) {
        let sound = BuddyResources.soundURL(name).flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: NSSound.Name(fallback))
        sound?.volume = Float(SoundSettings.volume()) / 3
        sound?.play()
    }

    private struct IconKey: Equatable {
        var pose: CreaturePose
        var cheer: CheerSize?
        var appearance: String
    }
    private var lastIcon: IconKey?

    private var appearanceObservation: NSKeyValueObservation?
    func start(engine: BuddyEngine) async {
        updateIcon(engine.state)
        appearanceObservation = NSApp?.observe(\.effectiveAppearance) { [weak self, weak engine] _, _ in
            Task { @MainActor in
                guard let engine else { return }
                self?.updateIcon(engine.state)
            }
        }
    }
    func stop() async { appearanceObservation = nil; lastIcon = nil }

    func stateDidChange(prev: BuddyState, next: BuddyState) {
        updateIcon(next)
        updateNotifications(prev: prev, next: next)
        playTransitionSounds(prev: prev, next: next)
        updateInteractiveMode(prev: prev, next: next)
    }

    private func updateIcon(_ state: BuddyState) {
        statusItem?.toolTip = state.creature.statusLabel
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let key = IconKey(pose: CreaturePose(from: state.creature), cheer: state.creature.cheer, appearance: appearance.name.rawValue)
        if key != lastIcon {
            lastIcon = key
            appearance.performAsCurrentDrawingAppearance {
                statusItem?.image = Self.statusIcon(for: state.creature)
            }
        }
        statusItem?.image?.accessibilityDescription = "Boop — " + state.creature.statusLabel
    }

    static func statusIcon(for creature: Creature) -> NSImage {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let renderer = ImageRenderer(content: MenuBarFace(creature: creature).environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.accessibilityDescription = "Boop — " + creature.statusLabel
        return image
    }

    private func updateNotifications(prev: BuddyState, next: BuddyState) {
        let previousPromptId = prev.prompt?.id
        let nextPrompt = next.prompt

        if let previousPromptId, previousPromptId != nextPrompt?.id {
            notifier.clearNotification(promptId: previousPromptId)
        }

        guard let nextPrompt, nextPrompt.id != previousPromptId else { return }
        if presenter?.isPopoverShown != true {
            notifier.postToolNotification(prompt: nextPrompt)
        }
    }

    private func playTransitionSounds(prev: BuddyState, next: BuddyState) {
        switch ChirpDecision.chirp(prev: prev, next: next, soundsEnabled: soundsEnabled()) {
        case .complete:   playCelebrate()
        case .attention:  playAttention()
        case .error:      playError()
        case nil:         break
        }
    }

    private func updateInteractiveMode(prev: BuddyState, next: BuddyState) {
        guard let presenter else { return }
        guard presenter.isInteractiveModeEnabled else {
            presenter.cancelPopoverAutoDismiss()
            return
        }
        guard prev.creature.state != next.creature.state else { return }

        if next.creature.state == .done
            && (next.lastTaskDurationMs ?? 0) >= 30_000
            && !presenter.isPopoverShown
        {
            presenter.showPopover(dismissAfter: 3.0)
        } else if next.creature.state == .needsYou && !presenter.isPopoverShown {
            presenter.showPopover(dismissAfter: 15.0)
        } else if (next.creature.state == .idle || next.creature.state == .asleep) && presenter.isPopoverShown {
            presenter.cancelPopoverAutoDismiss()
            presenter.closePopover()
        }
    }
}
