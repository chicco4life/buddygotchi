import AppKit
import Hummingbird
import ServiceLifecycle
import SwiftUI

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let engine = BuddyEngine()
    private var serverTask: Task<Void, Never>?
    private var serviceGroup: ServiceGroup?
    private var iconTimer: Timer?
    private var lastPromptId: String?
    private var lastIconSymbol: String?
    private var previousPetState: PetState = .sleep
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?
    private(set) var esp32Output: ESP32Output?
    private var autoDismissTimer: Timer?
    private let celebrateSound = NSSound(named: "Funk")
    private let attentionSound = NSSound(named: "Glass")
#if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.close() }

        setupSignalHandlers()
        configureUpdater()
        HookInstaller.shared.syncBundledHelpers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Buddygotchi")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.behavior = .transient
        NotificationManager.shared.setup(engine: engine)
        NotificationManager.shared.requestPermission()

        UserDefaults.standard.set(BuddyConfig.default.approvalMode, forKey: "approvalMode")

        let output = ESP32Output()
        esp32Output = output
        engine.register(output: output)

        engine.start()
        Task { await output.start(engine: engine) }

        let hostingController = NSHostingController(rootView: PopoverView(engine: engine, esp32Output: output))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        self.popover = popover

        serverTask = Task {
            let config = BuddyConfig.default
            let app = buildHookServer(engine: engine, config: config)
            let group = ServiceGroup(
                configuration: .init(
                    services: [app],
                    gracefulShutdownSignals: [],
                    logger: app.logger
                )
            )
            await MainActor.run { self.serviceGroup = group }
            try? await group.run()
        }

        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
        iconTimer?.invalidate()
        cancelAutoDismiss()
        if let esp32 = esp32Output {
            Task { await esp32.stop() }
        }
        engine.stop()
        if let group = serviceGroup {
            Task { await group.triggerGracefulShutdown() }
        }
        sigintSource?.cancel()
        sigtermSource?.cancel()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func setupSignalHandlers() {
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        src.setEventHandler {
            NSApp.terminate(nil)
        }
        src.resume()
        signal(SIGINT, SIG_IGN)
        sigintSource = src

        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler {
            NSApp.terminate(nil)
        }
        term.resume()
        signal(SIGTERM, SIG_IGN)
        sigtermSource = term
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            cancelAutoDismiss()
            popover.performClose(nil)
        } else {
            popover.behavior = .transient
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func tick() {
        let state = engine.state
        updateIcon(state)
        checkNotifications(state)
        checkSounds(state)
        checkInteractiveMode(state)
        previousPetState = state.pet.state
    }

    private func updateIcon(_ state: BuddyState) {
        let symbolName = state.pet.state.sfSymbol
        guard symbolName != lastIconSymbol else { return }
        lastIconSymbol = symbolName
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Buddygotchi")
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        if let updaterController {
            updaterController.checkForUpdates(nil)
        } else {
            NSSound.beep()
        }
#else
        NSSound.beep()
#endif
    }

    private func configureUpdater() {
#if canImport(Sparkle)
        guard Self.sparkleIsConfigured else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
#endif
    }

    private static var sparkleIsConfigured: Bool {
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.isEmpty,
              !publicKey.contains("REPLACE_WITH") else {
            return false
        }
        return true
    }

    private func checkNotifications(_ state: BuddyState) {
        let prompt = state.prompt

        if let prompt {
            if lastPromptId != prompt.id && !popover.isShown {
                NotificationManager.shared.postToolNotification(prompt: prompt)
            }
            lastPromptId = prompt.id
        } else if let old = lastPromptId {
            NotificationManager.shared.clearNotification(promptId: old)
            lastPromptId = nil
        }
    }

    private func checkSounds(_ state: BuddyState) {
        let current = state.pet.state
        guard current != previousPetState else { return }
        if current == .celebrate && (state.lastTaskDurationMs ?? 0) >= 30_000 {
            celebrateSound?.play()
        } else if current == .attention {
            attentionSound?.play()
        }
    }

    private func checkInteractiveMode(_ state: BuddyState) {
        let current = state.pet.state
        guard UserDefaults.standard.bool(forKey: "interactiveMode") else {
            cancelAutoDismiss()
            return
        }
        guard current != previousPetState else { return }

        if current == .celebrate
            && (state.lastTaskDurationMs ?? 0) >= 30_000
            && !popover.isShown
        {
            showPopover(dismissAfter: 3.0)
        } else if current == .attention && !popover.isShown {
            showPopover(dismissAfter: 15.0)
        } else if (current == .idle || current == .sleep) && popover.isShown {
            cancelAutoDismiss()
            popover.performClose(nil)
        }
    }

    private func showPopover(dismissAfter seconds: TimeInterval) {
        guard let button = statusItem.button else { return }
        cancelAutoDismiss()
        // Approvals use .transient so the user can dismiss; regular attention pins open.
        let isApproval = engine.state.prompt?.isApproval == true
        popover.behavior = isApproval ? .transient : .applicationDefined
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.autoDismissTimer = nil
                self?.popover.performClose(nil)
            }
        }
    }

    private func cancelAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }
}
