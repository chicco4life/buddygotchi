import AppKit
import Hummingbird
import ServiceLifecycle
import SwiftUI

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
    private var esp32Output: ESP32Output?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.close() }

        setupSignalHandlers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Buddygotchi")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(engine: engine)
        )
        self.popover = popover

        NotificationManager.shared.setup(engine: engine)
        NotificationManager.shared.requestPermission()

        engine.start()

        if UserDefaults.standard.string(forKey: "buddyOutput") == "m5stack" {
            let output = ESP32Output()
            esp32Output = output
            engine.register(output: output)
            Task { await output.start(engine: engine) }
        }

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
            popover.performClose(nil)
            popover.behavior = .transient
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
        checkInteractiveMode(state)
    }

    private func updateIcon(_ state: BuddyState) {
        let symbolName = state.pet.state.sfSymbol
        guard symbolName != lastIconSymbol else { return }
        lastIconSymbol = symbolName
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Buddygotchi")
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

    private func checkInteractiveMode(_ state: BuddyState) {
        let currentPetState = state.pet.state
        defer { previousPetState = currentPetState }

        guard UserDefaults.standard.bool(forKey: "interactiveMode") else {
            if popover.behavior == .applicationDefined {
                popover.behavior = .transient
            }
            return
        }

        guard currentPetState != previousPetState else { return }

        let activeStates: Set<PetState> = [.attention]
        let inactiveStates: Set<PetState> = [.idle, .sleep]

        if activeStates.contains(currentPetState) && !popover.isShown {
            showPopoverForInteractiveMode()
        } else if inactiveStates.contains(currentPetState) && popover.isShown {
            popover.performClose(nil)
            popover.behavior = .transient
        }
    }

    private func showPopoverForInteractiveMode() {
        guard let button = statusItem.button else { return }
        popover.behavior = .applicationDefined
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
