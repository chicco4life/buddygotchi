import AppKit
import BoopKit
import SwiftUI

/// The menu-bar app (UX.md §7): an icon that mirrors Boop and a popover. It
/// never pops up by itself and never sends notifications.
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

/// What the views show. Updated on the main thread only.
@MainActor
final class AppModel: ObservableObject {
    @Published var status: Runtime.Status?
    @Published var hooks: [HookInstaller.Agent: HookInstaller.Health] = [:]
    @Published var remembered: [String] = []
    @Published var restartAgents = false
    @Published var brain = "apple"
    @Published var name = ""

    let installer: HookInstaller
    var runtime: Runtime?

    init(installer: HookInstaller) {
        self.installer = installer
        refreshHooks()
    }

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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let stateDir: URL
    let link: LinkSetting
    let log: LogFile
    let model: AppModel
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    var windows: [NSWindow] = []
    var runtime: Runtime?
    var listener: SpeechListener?

    init(stateDir: URL, link: LinkSetting) {
        self.stateDir = stateDir
        self.link = link
        log = LogFile(directory: stateDir, echo: false)
        model = AppModel(installer: HookInstaller(home: URL(fileURLWithPath: NSHomeDirectory()),
                                                  hookPath: stateDir.appendingPathComponent("bin/boop-hook").path))
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

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        updateIcon(nil)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model, delegate: self))

        let memory = try? MemoryStore(directory: stateDir, steering: "")
        if memory?.isSetUp == true {
            startRuntime()
        } else {
            showSetup()
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
            log.write("hooks: no boop-hook next to the app")
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
            runtime.onChange = { [weak self] status in Task { @MainActor in self?.show(status) } }
            runtime.onListen = { (on: Bool) in
                if on {
                    listener.start()
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
            model.name = runtime.memory.longTerm?.name ?? "Boop"
            listener.authorize { ok in if !ok { log.write("talk: speech or microphone access was refused") } }
        } catch {
            log.write("boop: can't start: \(error)")
        }
    }

    func show(_ status: Runtime.Status) {
        model.status = status
        updateIcon(status.snapshot)
    }

    /// A dot while agents work, amber when something needs you.
    func updateIcon(_ snapshot: StateSnapshot?) {
        guard let button = statusItem?.button else { return }
        let waiting = (snapshot?.wait ?? 0) > 0
        let working = (snapshot?.busy ?? 0) > 0
        let symbol = waiting || working ? "circle.fill" : "circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Boop")
        image?.isTemplate = !waiting
        button.image = image
        button.contentTintColor = waiting ? NSColor(red: 1, green: 0.69, blue: 0.2, alpha: 1) : nil
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshHooks()
            runtime?.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showSettings() {
        popover.performClose(nil)
        model.loadRemembered()
        open(SettingsView(model: model), title: "Boop Settings")
    }

    func showSetup() {
        open(SetupView(model: model) { [weak self] name, nature, agents in self?.finishSetup(name, nature, agents) },
             title: "Meet Boop")
    }

    func finishSetup(_ name: String, _ nature: LongTerm.Nature, _ agents: [HookInstaller.Agent]) {
        do {
            try Runtime.setUp(stateDir: stateDir, name: name, nature: nature,
                              today: LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)))
        } catch {
            log.write("setup: \(error)")
            return
        }
        for agent in agents { model.install(agent) }
        windows.forEach { $0.close() }
        windows.removeAll()
        startRuntime()
    }

    func open<V: View>(_ view: V, title: String) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
