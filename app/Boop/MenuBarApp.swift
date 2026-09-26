import AppKit
import BoopKit
import SwiftUI

/// The menu-bar app (UX.md §7): an icon that mirrors Boop and a popover.
/// Setup and settings open inside the popover. It pops up by itself only
/// once, on first launch, to show setup, and never sends notifications.
enum MenuBarApp {
    static func run(_ args: [String]) -> Never {
        let stateDir = option(args, "--state-dir").map { URL(fileURLWithPath: $0) } ?? AppSettings.defaultStateDir()
        guard let link = LinkSetting(option(args, "--link") ?? "ble") else { fail("--link is ble, usb:SOCKET or none") }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate(stateDir: stateDir, link: link)
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
        exit(0)
    }
}

enum Pane: Equatable {
    case overview, settings, setup
}

/// What the person has chosen so far in setup. It lives in the model, so
/// closing the popover halfway through loses nothing.
struct SetupDraft {
    enum Step: Int, CaseIterable {
        case hello, name, agents, ready
    }

    var step = Step.hello
    var name = ""
    var nature = LongTerm.Nature.sweet
    var agents = Set(HookInstaller.Agent.allCases)
    var error: String?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// What the views show. Updated on the main thread only.
@MainActor
final class AppModel: ObservableObject {
    @Published var pane = Pane.overview
    @Published var setup = SetupDraft()
    @Published var status: Runtime.Status?
    @Published var hooks: [HookInstaller.Agent: HookInstaller.Health] = [:]
    @Published var remembered: [String] = []
    @Published var restartAgents = false
    /// The brain chosen in settings; `status.brain` is the one running.
    @Published var brain = "apple"
    @Published var nature = LongTerm.Nature.sweet
    @Published var startError: String?
    /// Why push-to-talk couldn't hear you, until the next try.
    @Published var talkError: String?

    let installer: HookInstaller
    let link: LinkSetting
    var runtime: Runtime?
    var finishSetup: () -> Void = {}

    init(installer: HookInstaller, link: LinkSetting) {
        self.installer = installer
        self.link = link
        refreshHooks()
    }

    var name: String { status?.snapshot.name ?? "Boop" }

    func refreshHooks() {
        hooks = Dictionary(uniqueKeysWithValues: HookInstaller.Agent.allCases.map { ($0, installer.health($0)) })
    }

    func install(_ agent: HookInstaller.Agent) {
        try? installer.install(agent)
        restartAgents = true
        refreshHooks()
    }

    func remove(_ agent: HookInstaller.Agent) {
        try? installer.remove(agent)
        restartAgents = true
        refreshHooks()
    }

    func loadRemembered() {
        runtime?.remembered { lines in Task { @MainActor in self.remembered = lines } }
    }

    func forget(_ line: String) {
        runtime?.forget(line)
        remembered.removeAll { $0 == line }
    }

    // The switches show the change at once; the runtime's next status confirms it.

    func setFocus(_ on: Bool) {
        status?.snapshot.focus = on
        runtime?.setFocus(on)
    }

    func setAway(_ on: Bool) {
        status?.away = on
        runtime?.setAway(on)
    }

    func setVolume(_ volume: Int) {
        guard status?.snapshot.vol != volume else { return }
        status?.snapshot.vol = volume
        runtime?.setVolume(volume)
    }

    var listening: Bool { status?.listening == true }

    /// The Talk button: click to talk, click again to send.
    func toggleTalk() {
        let on = !listening
        if on { talkError = nil }
        status?.listening = on
        runtime?.setListening(on)
    }

    func setBrain(_ brain: String) {
        self.brain = brain
        runtime?.setBrain(brain)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let stateDir: URL
    let link: LinkSetting
    let log: LogFile
    let model: AppModel
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    var runtime: Runtime?
    var listener: SpeechListener?

    init(stateDir: URL, link: LinkSetting) {
        self.stateDir = stateDir
        self.link = link
        log = LogFile(directory: stateDir, echo: false)
        model = AppModel(installer: HookInstaller(home: URL(fileURLWithPath: NSHomeDirectory()),
                                                  hookPath: stateDir.appendingPathComponent("bin/boop-hook").path),
                         link: link)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        placeHookClient()
        let repaired = model.installer.repair()
        if !repaired.isEmpty {
            log.write("hooks: repaired \(repaired.map(\.rawValue).joined(separator: ", "))")
            model.restartAgents = true
        }
        model.refreshHooks()
        model.finishSetup = { [weak self] in self?.finishSetup() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "Boop"
        statusItem = item
        updateIcon(nil)

        let host = NSHostingController(rootView: PopoverView(model: model) { [weak self] in self?.popover.performClose(nil) })
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        // Panes change height; an animated resize would clip them mid-way.
        popover.animates = false
        popover.delegate = self

        let memory = try? MemoryStore(directory: stateDir, steering: "")
        if memory?.isSetUp == true {
            startRuntime()
        } else {
            // First launch: open the popover on setup, once, so the person
            // sees where Boop lives.
            model.pane = .setup
            model.setup.agents = Set(HookInstaller.Agent.allCases.filter(model.installer.detected))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
    }

    /// The hooks call a stable copy of `boop-hook` in the state directory, so
    /// a rebuilt or moved app doesn't break them.
    func placeHookClient() {
        let fm = FileManager.default
        guard let built = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("boop-hook"),
              fm.isExecutableFile(atPath: built.path) else {
            let placed = model.installer.clientInPlace ? "keeping the copy in place" : "hooks can't be installed or repaired"
            log.write("hooks: no boop-hook next to the app; \(placed)")
            return
        }
        let target = URL(fileURLWithPath: model.installer.hookPath)
        if fm.contentsEqual(atPath: built.path, andPath: target.path) { return }
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staged = target.appendingPathExtension("new")
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: built, to: staged)
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } catch {
            log.write("hooks: can't place boop-hook: \(error)")
        }
    }

    func startRuntime() {
        let transport: DeviceTransport? = switch link {
        case .bluetooth: BLETransport()
        case .usb(let path): USBTransport(path: path)
        case .none: nil
        }
        let log = self.log
        var options = Runtime.Options(stateDir: stateDir, socketPath: stateDir.appendingPathComponent("boop.sock").path, link: transport,
                                      steering: bundledSteering())
        options.log = { log.write($0) }
        do {
            let runtime = try Runtime(options)
            let listener = SpeechListener(log: { log.write($0) })
            let model = self.model
            runtime.onChange = { [weak self] status in Task { @MainActor in self?.show(status) } }
            runtime.onListen = { (on: Bool) in
                if on {
                    listener.start { why in
                        log.write("talk: \(why)")
                        runtime.micFailed()
                        Task { @MainActor in model.talkError = why }
                    }
                } else {
                    listener.stop { words in
                        if let words { runtime.talk(words) } else { log.write("talk: heard nothing") }
                    }
                }
            }
            try runtime.start()
            self.runtime = runtime
            self.listener = listener
            model.runtime = runtime
            model.brain = runtime.settings.brain
            model.nature = runtime.memory.longTerm?.nature ?? .sweet
            model.startError = nil
            runtime.refresh()
        } catch {
            log.write("boop: can't start: \(error)")
            model.startError = "\(error)"
        }
    }

    func show(_ status: Runtime.Status) {
        model.status = status
        updateIcon(status)
    }

    func updateIcon(_ status: Runtime.Status?) {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarIcon.image(FaceMood(status))
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        model.refreshHooks()
        runtime?.refresh()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Settings closes back to the overview; setup stays where it was.
    func popoverDidClose(_ notification: Notification) {
        if model.pane == .settings { model.pane = .overview }
    }

    func finishSetup() {
        let draft = model.setup
        do {
            try Runtime.setUp(stateDir: stateDir, name: draft.trimmedName, nature: draft.nature,
                              today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        } catch {
            log.write("setup: \(error)")
            model.setup.error = "Boop couldn't save its memory: \(error)"
            return
        }
        for agent in HookInstaller.Agent.allCases where draft.agents.contains(agent) && model.installer.detected(agent) {
            model.install(agent)
        }
        startRuntime()
        withAnimation(.boopSettle) { model.pane = .overview }
    }
}
