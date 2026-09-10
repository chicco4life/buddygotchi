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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controlPopover: NSPopover!
    private let controlNavigation = ControlNavigation()
    private let engine = BuddyEngine(defaults: AppDefaults.shared)
    private var serverTask: Task<Void, Never>?
    private var serviceGroup: ServiceGroup?
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?
    private(set) var esp32Output: ESP32Output?
    private var autoDismissTimer: Timer?
    private let serverHealth = ServerHealth()
    private let instanceLock = BuddyConfig.default.headless
        ? InstanceLock(path: "\(BuddyConfig.default.stateDir)/instance.lock")
        : InstanceLock()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Inherit the system appearance for both the menu bar icon and popover.
        NSApp.windows.forEach { $0.close() }
        registerBundledFonts()

        guard claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        setupSignalHandlers()
        let config = BuddyConfig.default
        AppDefaults.shared.set(config.approvalMode, forKey: DefaultsKey.approvalMode)
        engine.setSpecies(AppDefaults.shared.string(forKey: DefaultsKey.buddySpecies) ?? Pet.defaultSpecies)

        if config.headless {
            engine.register(output: DesktopOutput(statusItem: nil, presenter: self, soundsEnabled: { false }))
        } else {
            SparkleUpdateManager.shared.start()
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.image = DesktopOutput.statusIcon(for: Creature.initial)
                button.action = #selector(statusItemClicked)
                button.target = self
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }

            let output = ESP32Output(defaults: AppDefaults.shared)
            esp32Output = output
            engine.register(output: output)
            Task { await output.start(engine: engine) }
            Task { await verifyManagedHooksAfterLaunch() }

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            NotificationManager.shared.setup(engine: engine) { [weak self] in
                self?.showPopover()
            }
            let hostingController = NSHostingController(
                rootView: PopoverView(
                    engine: engine,
                    esp32Output: output,
                    serverHealth: serverHealth,
                    onUserInteraction: { [weak self] in self?.cancelAutoDismiss() },
                    onOpenOnboarding: { [weak self] in self?.showSetup() },
                    onClose: { [weak self] in self?.closePopover() },
                    navigation: controlNavigation
                )
            )
            hostingController.sizingOptions = .preferredContentSize
            popover.contentViewController = hostingController
            self.controlPopover = popover
            engine.register(output: DesktopOutput(statusItem: statusItem, presenter: self))
        }
        engine.start()

        serverTask = Task {
            let app = buildHookServer(
                engine: engine,
                config: config,
                onListening: { @MainActor [weak self] in
                    self?.serverHealth.status = .listening(port: config.httpPort)
                }
            )
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

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !BuddyConfig.default.headless else { return false }
        controlNavigation.pane = .overview
        showPopover()
        return true
    }

    /// Flush in-flight store work, then terminate. Never `.terminateLater`:
    /// AppKit waits for that reply in a modal run-loop mode where main-actor
    /// tasks do not run, so the reply never comes and SIGTERM becomes a no-op.
    private var terminating = false
    func requestTerminate() {
        guard !terminating else { return }
        terminating = true
        Task { @MainActor in
            let flush = Task { @MainActor in await self.engine.finishPendingWork() }
            // First to finish wins: the flush, or a two-second deadline.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await flush.value }
                group.addTask { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                await group.next()
                group.cancelAll()
            }
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !terminating { requestTerminate(); return .terminateCancel }
        return .terminateNow
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
        src.setEventHandler { [weak self] in self?.requestTerminate() }
        src.resume()
        signal(SIGINT, SIG_IGN)
        sigintSource = src

        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { [weak self] in self?.requestTerminate() }
        term.resume()
        signal(SIGTERM, SIG_IGN)
        sigtermSource = term
    }

    private func claimSingleInstance() -> Bool {
        if BuddyConfig.default.headless { return instanceLock.tryClaim() }
        if let bundleIdentifier = AppMetadata.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
            if let existing = matches.first {
                if !BuddyConfig.default.headless { existing.activate() }
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
        guard statusItem?.button != nil else { return }
        if controlPopover.isShown {
            cancelAutoDismiss()
            closePopover()
        } else {
            controlNavigation.pane = .overview
            showPopover()
        }
    }

    private func showSetup() {
        controlNavigation.pane = .setup
        showPopover()
    }

    private func showPopover() {
        guard let controlPopover, let button = statusItem?.button else { return }
        cancelAutoDismiss()
        engine.refreshSettings()
        engine.popoverVisible = true
        NSApp.activate(ignoringOtherApps: true)
        controlPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        controlPopover.contentViewController?.view.window?.makeKey()
    }

    @objc private func openSettingsFromMenu() {
        controlNavigation.pane = .settings
        showPopover()
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

    static func presentShareCard(engine: BuddyEngine) {
        Task { @MainActor in
            do {
                let image = try engine.shareCard().cgImage()
                let (url, png) = try await Task.detached {
                    let png = try ShareCard.pngData(image)
                    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent("Boop-share-\(UUID().uuidString).png")
                    try png.write(to: url, options: .atomic)
                    return (url, png)
                }.value
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(png, forType: .png)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { NSAlert(error: error).runModal() }
        }
    }

    @objc private func shareCardFromMenu() { Self.presentShareCard(engine: engine) }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: BuddyCopy.phase7("shareCard", language: engine.state.language), action: #selector(shareCardFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.openBoop, action: #selector(togglePopover), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.settings, action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.checkForUpdates, action: #selector(checkForUpdatesFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: BuddyCopy.shared.appMenu.quit, action: #selector(quitFromMenu), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem.menu = nil
    }

    func showPopover(dismissAfter seconds: TimeInterval) {
        controlNavigation.pane = .overview
        showPopover()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.autoDismissTimer = nil
                self?.closePopover()
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
            HookInstaller.shared.unregisterMCP(for: agent)
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
        controlPopover?.isShown == true
    }

    var isInteractiveModeEnabled: Bool {
        false
    }

    func closePopover() {
        engine.popoverVisible = false
        controlPopover?.performClose(nil)
    }

    func cancelPopoverAutoDismiss() {
        cancelAutoDismiss()
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) { engine.popoverVisible = false; cancelAutoDismiss() }
}
