import AppKit
import BoopKit
import SwiftUI

/// `Boop --snapshots DIR`: renders the popover's panes and the menu-bar
/// icons to PNGs, in light and dark, from fixed fixtures, then exits
/// (VERIFICATION.md L0). No runtime, no Bluetooth, no microphone, and the
/// agents' settings it reads are in a throwaway HOME.
@MainActor
enum Snapshots {
    static func run(_ args: [String]) -> Never {
        guard let dir = option(args, "--snapshots") else { fail("--snapshots needs a directory") }
        let out = URL(fileURLWithPath: dir)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("boop-snapshots-\(getpid())")
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            // The installer refuses without a boop-hook to call, so give it one.
            let hook = home.appendingPathComponent("bin/boop-hook")
            try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            let installer = HookInstaller(home: home, hookPath: hook.path)
            let unbuilt = HookInstaller(home: home, hookPath: home.appendingPathComponent("bin/missing").path)

            for dark in [false, true] {
                let look = dark ? "dark" : "light"
                for (name, model) in overviews(installer) {
                    render(PopoverView(model: model, maxHeight: 2000), "overview-\(name)-\(look)", dark: dark, to: out)
                }
                let settings = model(installer, status: status(threads: [["codex", "landing", "work"]]))
                settings.pane = .settings
                settings.remembered = ["Ships on Fridays.", "Likes tests before lunch."]
                try? installer.install(.claude)
                settings.refreshHooks()
                settings.restartAgents = true
                render(PopoverView(model: settings, maxHeight: 2000), "settings-\(look)", dark: dark, to: out)
                try? installer.remove(.claude)
                let noHook = model(unbuilt, status: status())
                noHook.pane = .settings
                render(PopoverView(model: noHook, maxHeight: 2000), "settings-no-hook-\(look)", dark: dark, to: out)

                for step in SetupDraft.Step.allCases {
                    let setup = model(installer, status: nil)
                    setup.pane = .setup
                    setup.setup.step = step
                    setup.setup.agents = [.claude]
                    if step.rawValue >= SetupDraft.Step.name.rawValue { setup.setup.name = "Mochi" }
                    render(PopoverView(model: setup), "setup-\(step.rawValue + 1)-\(step)-\(look)", dark: dark, to: out)
                }
                let setup = model(unbuilt, status: nil)
                setup.pane = .setup
                setup.setup.step = .agents
                setup.setup.agents = [.claude]
                setup.setup.name = "Mochi"
                render(PopoverView(model: setup), "setup-3-agents-no-hook-\(look)", dark: dark, to: out)
                renderIcons(dark: dark, to: out)
            }
        } catch {
            fail("snapshots: \(error)")
        }
        exit(0)
    }

    static func model(_ installer: HookInstaller, status: Runtime.Status?) -> AppModel {
        let model = AppModel(installer: installer, link: .bluetooth)
        model.status = status
        return model
    }

    static func status(base: String = "working", threads: [[String]] = [], focus: Bool = false, quiet: Int = 0,
                       vol: Int = 6, away: Bool = false, connected: Bool = true, listening: Bool = false) -> Runtime.Status {
        let wait = threads.filter { $0[2] == "wait" }
        let snapshot = StateSnapshot(
            time: 1_790_000_000, name: "Mochi", base: base,
            attn: wait.first.map { StateSnapshot.Attention(agent: $0[0], project: $0[1], more: wait.count - 1) },
            busy: threads.filter { $0[2] == "work" }.count, idle: threads.filter { $0[2] == "idle" }.count,
            wait: wait.count, mood: Mood(), quiet: quiet, focus: focus, vol: vol, night: false,
            level: 4, prog: 62, days: 12, hungry: 0, threads: threads)
        return Runtime.Status(snapshot: snapshot, connected: connected,
                              device: connected ? DeviceStatus(id: "b00p-54fe", fw: "1.0.0") : nil,
                              brain: "apple", away: away, finished: 148, projects: 6, listening: listening)
    }

    static func overviews(_ installer: HookInstaller) -> [(String, AppModel)] {
        [
            ("asleep", model(installer, status: status(base: "asleep"))),
            ("working", model(installer, status: status(threads: [
                ["codex", "landing", "work"], ["codex", "buddygotchi", "work"],
                ["claude", "jetpack", "work"], ["claude", "notes", "idle"],
            ]))),
            ("needs-you", model(installer, status: status(threads: [
                ["codex", "landing", "wait"], ["claude", "jetpack", "wait"],
                ["codex", "buddygotchi", "work"], ["claude", "notes", "idle"],
            ], focus: true, quiet: 8))),
            ("listening", model(installer, status: status(threads: [["claude", "jetpack", "work"]], listening: true))),
            ("mic-refused", {
                let m = model(installer, status: status(base: "idle", threads: [["claude", "jetpack", "idle"]]))
                m.talkError = "Allow Boop in System Settings → Privacy & Security → Microphone."
                return m
            }()),
            ("offline", {
                let m = model(installer, status: status(base: "idle", threads: [["claude", "jetpack", "idle"]],
                                                        vol: 0, away: true, connected: false))
                m.restartAgents = true
                return m
            }()),
            ("not-running", {
                let m = model(installer, status: nil)
                m.startError = "Another Boop is already running."
                return m
            }()),
        ]
    }

    // MARK: Rendering

    private static let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

    static func render<V: View>(_ view: V, _ name: String, dark: Bool, to dir: URL) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.stillMotion, true)
            .environment(\.controlActiveState, .key))
        host.appearance = appearance
        window.appearance = appearance
        window.contentView = host
        // Size to the content, twice: scroll panes measure themselves on
        // the first pass and settle on the second.
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            host.frame = CGRect(origin: .zero, size: size)
            window.setContentSize(size)
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fail("snapshots: \(name) has no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("snapshots: \(name) has no PNG") }
        let url = dir.appendingPathComponent("\(name).png")
        do { try png.write(to: url) } catch { fail("snapshots: can't write \(url.path): \(error)") }
        print("\(name).png \(Int(host.bounds.width))×\(Int(host.bounds.height))")
    }

    /// Every icon on a light and a dark menu bar, drawn at 4× so it can be judged.
    static func renderIcons(dark: Bool, to dir: URL) {
        let moods: [FaceMood] = [.asleep, .idle, .working, .needsYou, .listening]
        let icon = MenuBarIcon.image(.idle).size
        let pad: CGFloat = 10, gap: CGFloat = 14, scale: CGFloat = 4
        let size = NSSize(width: 2 * pad + CGFloat(moods.count) * icon.width + CGFloat(moods.count - 1) * gap, height: 24)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { fail("snapshots: no icon bitmap") }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: dark ? 0.16 : 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let ink = dark ? NSColor.white : NSColor(white: 0, alpha: 0.85)
        for (i, mood) in moods.enumerated() {
            let rect = NSRect(x: pad + CGFloat(i) * (icon.width + gap), y: (size.height - icon.height) / 2,
                              width: icon.width, height: icon.height)
            let image = MenuBarIcon.image(mood)
            if image.isTemplate {
                // A template image takes the menu bar's colour.
                NSImage(size: icon, flipped: false) { r in
                    image.draw(in: r)
                    ink.set()
                    r.fill(using: .sourceAtop)
                    return true
                }.draw(in: rect)
            } else {
                image.draw(in: rect)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "menubar-\(dark ? "dark" : "light")"
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("snapshots: \(name) has no PNG") }
        do { try png.write(to: dir.appendingPathComponent("\(name).png")) } catch { fail("snapshots: \(error)") }
        print("\(name).png")
    }
}
