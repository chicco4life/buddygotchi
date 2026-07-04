import AppKit
import Hummingbird
import Observation
import ServiceLifecycle
import SwiftUI

@Observable
@MainActor
final class ServerHealth {
    enum Status: Equatable {
        case starting
        case listening(port: Int)
        case failed(reason: String)
    }

    var status: Status = .starting
}

extension Notification.Name {
    static let buddygotchiOpenSettings = Notification.Name("buddygotchiOpenSettings")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let engine = BuddyEngine()
    private var serverTask: Task<Void, Never>?
    private var serviceGroup: ServiceGroup?
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?
    private(set) var esp32Output: ESP32Output?
    private var autoDismissTimer: Timer?
    private var onboardingWindowController: OnboardingWindowController?
    private let serverHealth = ServerHealth()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.windows.forEach { $0.close() }

        setupSignalHandlers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Buddygotchi")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        NotificationManager.shared.setup(engine: engine) { [weak self] in
            self?.showPopover()
        }
        NotificationManager.shared.requestPermission()

        let config = BuddyConfig.default
        UserDefaults.standard.set(config.approvalMode, forKey: "approvalMode")
        engine.setSpecies(UserDefaults.standard.string(forKey: "buddySpecies") ?? Pet.defaultSpecies)

        let output = ESP32Output()
        esp32Output = output
        engine.register(output: output)

        engine.start()
        Task { await output.start(engine: engine) }

        let hostingController = NSHostingController(
            rootView: PopoverView(
                engine: engine,
                esp32Output: output,
                serverHealth: serverHealth,
                onUserInteraction: { [weak self] in self?.cancelAutoDismiss() },
                onOpenOnboarding: { [weak self] in self?.showOnboardingWindow() }
            )
        )
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        self.popover = popover

        engine.register(output: DesktopOutput(statusItem: statusItem, presenter: self))

        serverTask = Task {
            let app = buildHookServer(engine: engine, config: config)
            await MainActor.run {
                self.serverHealth.status = .listening(port: config.httpPort)
            }
            let group = ServiceGroup(
                configuration: .init(
                    services: [app],
                    gracefulShutdownSignals: [],
                    logger: app.logger
                )
            )
            await MainActor.run { self.serviceGroup = group }
            do {
                try await group.run()
                await MainActor.run {
                    self.serverHealth.status = .failed(reason: "server stopped unexpectedly")
                }
            } catch {
                await MainActor.run {
                    self.serverHealth.status = .failed(reason: error.localizedDescription)
                }
            }
        }

        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            showOnboardingWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !UserDefaults.standard.bool(forKey: "setupCompleted") {
            showOnboardingWindow()
        } else {
            showPopover()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    private func cleanup() {
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

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard statusItem.button != nil else { return }
        if popover.isShown {
            cancelAutoDismiss()
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showOnboardingWindow() {
        if onboardingWindowController == nil || onboardingWindowController?.window?.isVisible != true {
            onboardingWindowController = OnboardingWindowController(
                engine: engine,
                esp32Output: esp32Output ?? ESP32Output(),
                onFinish: { [weak self] in
                    self?.onboardingWindowController?.close()
                    self?.onboardingWindowController = nil
                    UserDefaults.standard.set(true, forKey: "showMenuHint")
                    self?.showPopover()
                }
            )
        }
        onboardingWindowController?.show()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        cancelAutoDismiss()
        popover.behavior = .transient
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func openSettingsFromMenu() {
        showPopover()
        NotificationCenter.default.post(name: .buddygotchiOpenSettings, object: nil)
    }

    @objc private func checkForUpdatesFromMenu() {
        openSettingsFromMenu()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Buddygotchi", action: #selector(togglePopover), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func showPopover(isApproval: Bool, dismissAfter seconds: TimeInterval) {
        guard let button = statusItem.button else { return }
        cancelAutoDismiss()
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

extension AppDelegate: PopoverPresenting {
    var isPopoverShown: Bool {
        popover?.isShown == true
    }

    var isInteractiveModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "interactiveMode")
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    func cancelPopoverAutoDismiss() {
        cancelAutoDismiss()
    }
}
