import AppKit
import CoreText
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
    static let boopOpenSettings = Notification.Name("boopOpenSettings")
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
    private let instanceLock = InstanceLock()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Deliberately left unset. Boop's own surfaces pin themselves to .aqua,
        // but the status item is not a Boop surface -- it belongs to the menu bar,
        // and NSColor.labelColor inside DesktopOutput.statusIcon can only resolve
        // correctly on both light and dark menu bars if the app inherits the
        // system appearance. Pinning it here made the icon near-invisible on a
        // light menu bar.
        NSApp.windows.forEach { $0.close() }
        registerBundledFonts()

        guard claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        setupSignalHandlers()
        SparkleUpdateManager.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = DesktopOutput.statusIcon(for: .sleep)
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .aqua)
        NotificationManager.shared.setup(engine: engine) { [weak self] in
            self?.showPopover()
        }

        let config = BuddyConfig.default
        UserDefaults.standard.set(config.approvalMode, forKey: DefaultsKey.approvalMode)
        engine.setSpecies(UserDefaults.standard.string(forKey: DefaultsKey.buddySpecies) ?? Pet.defaultSpecies)

        let output = ESP32Output()
        esp32Output = output
        engine.register(output: output)

        engine.start()
        Task { await output.start(engine: engine) }
        Task { await verifyManagedHooksAfterLaunch() }

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
            let app = buildHookServer(
                engine: engine,
                config: config
            )
            let group = ServiceGroup(
                configuration: .init(
                    services: [app],
                    gracefulShutdownSignals: [],
                    logger: app.logger
                )
            )
            await MainActor.run { self.serviceGroup = group }
            let listeningTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.serverHealth.status = .listening(port: config.httpPort)
                }
            }
            do {
                try await group.run()
                listeningTask.cancel()
                await MainActor.run {
                    self.serverHealth.status = .failed(reason: "server stopped unexpectedly")
                }
            } catch {
                listeningTask.cancel()
                await MainActor.run {
                    self.serverHealth.status = .failed(reason: error.localizedDescription)
                }
            }
        }

        if !UserDefaults.standard.bool(forKey: DefaultsKey.setupCompleted) {
            showOnboardingWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !UserDefaults.standard.bool(forKey: DefaultsKey.setupCompleted) {
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
        // Unblock any hooks parked on an approval BEFORE the server goes away:
        // a clean passthrough response lets the agent fall back to its native
        // prompt immediately, instead of a connection reset — and a request
        // stuck on a continuation can't hold up graceful shutdown.
        engine.resolveAllPendingApprovals(decision: .passthrough)
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

    private func claimSingleInstance() -> Bool {
        if let bundleIdentifier = AppMetadata.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
            if let existing = matches.first {
                existing.activate()
                return false
            }
        }
        // The bundle check can't see a `swift run` debug binary (no bundle),
        // and that binary can't see the app — the flock is the arbiter that
        // works across both, so a forgotten debug instance can't keep
        // feeding the device empty heartbeats. Escape hatch for anyone who
        // genuinely needs two: BOOP_ALLOW_SECOND_INSTANCE=1.
        if ProcessInfo.processInfo.environment["BOOP_ALLOW_SECOND_INSTANCE"] == "1" {
            return true
        }
        return instanceLock.tryClaim()
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
        guard let esp32Output else {
            preconditionFailure("ESP32Output must be initialized before showing onboarding")
        }
        if onboardingWindowController == nil || onboardingWindowController?.window?.isVisible != true {
            onboardingWindowController = OnboardingWindowController(
                engine: engine,
                esp32Output: esp32Output,
                onFinish: { [weak self] in
                    self?.onboardingWindowController?.close()
                    self?.onboardingWindowController = nil
                    UserDefaults.standard.set(true, forKey: DefaultsKey.showMenuHint)
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
        NotificationCenter.default.post(name: .boopOpenSettings, object: nil)
    }

    @objc private func checkForUpdatesFromMenu() {
        if SparkleUpdateManager.shared.isAvailable {
            SparkleUpdateManager.shared.checkForUpdates()
        } else {
            openSettingsFromMenu()
        }
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.openBoop, action: #selector(togglePopover), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.settings, action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.checkForUpdates, action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.quit, action: #selector(quitFromMenu), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func showPopover(dismissAfter seconds: TimeInterval) {
        guard let button = statusItem.button else { return }
        cancelAutoDismiss()
        popover.behavior = .transient
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

    private func registerBundledFonts() {
        BuddyResources.registerFonts()
    }

    private func verifyManagedHooksAfterLaunch() async {
        let tracked = Set(HookInstaller.shared.previouslyInstalledAgents())
        let healthByAgent = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { agent in
                (agent, HookInstaller.shared.verify(agent: agent))
            }
        )
        let agents = AgentKind.allCases.filter { agent in
            tracked.contains(agent) || healthByAgent[agent] != .notInstalled
        }
        for agent in agents {
            guard let health = healthByAgent[agent] else { continue }
            switch health {
            case .installed:
                engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "verify", detail: "installed")
            case .outdated(let installed, let current):
                do {
                    try HookInstaller.shared.repair(agent: agent)
                    engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "repair", detail: "updated hooks from v\(installed) to v\(current)")
                } catch {
                    engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "repair-failed", detail: error.localizedDescription)
                }
            case .corrupted(let reason) where health.repairable:
                do {
                    try HookInstaller.shared.repair(agent: agent)
                    engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "repair", detail: reason)
                } catch {
                    engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "repair-failed", detail: error.localizedDescription)
                }
            case .corrupted(let reason):
                engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "verify-failed", detail: reason)
            case .notInstalled:
                engine.diagnosticLog.log(category: "hooks", source: agent.rawValue, event: "verify", detail: "not installed")
            }
        }
    }
}

extension AppDelegate: PopoverPresenting {
    var isPopoverShown: Bool {
        popover?.isShown == true
    }

    var isInteractiveModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.interactiveMode)
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    func cancelPopoverAutoDismiss() {
        cancelAutoDismiss()
    }
}
