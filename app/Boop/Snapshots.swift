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
                let settings = model(installer, status: status(sessions: [["codex", "landing", "work"]]))
                settings.pane = .settings
                settings.remembered = ["Ships on Fridays.", "Likes tests before lunch."]
                try? installer.install(.claude)
                settings.refreshHooks()
                settings.restartAgents = true
                render(PopoverView(model: settings, maxHeight: 2000), "settings-\(look)", dark: dark, to: out)
                try? installer.remove(.claude)
                let chatty = model(installer, status: status(mode: .chatty))
                chatty.mode = .chatty
                chatty.pane = .settings
                render(PopoverView(model: chatty, maxHeight: 2000), "settings-chatty-\(look)", dark: dark, to: out)
                let noHook = model(unbuilt, status: status())
                noHook.pane = .settings
                render(PopoverView(model: noHook, maxHeight: 2000), "settings-no-hook-\(look)", dark: dark, to: out)
                // Normal without Jev's key, the body away and Claude's hooks needing a repair.
                let offline = model(installer, status: status(connected: false, classifier: "chatty@1"))
                offline.pane = .settings
                offline.hooks[.claude] = .outdated
                render(PopoverView(model: offline, maxHeight: 2000), "settings-offline-nokey-\(look)", dark: dark, to: out)

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

    static func model(_ installer: HookInstaller, status: Runtime.Status?, link: LinkSetting = .bluetooth) -> AppModel {
        let model = AppModel(installer: installer, link: link)
        model.status = status
        model.readKey = { nil }  // fixtures only: never the real Keychain
        return model
    }

    /// `sessions` are agent, project and `wait`, `work` or `idle`.
    static func status(base: String = "working", sessions rows: [[String]] = [], quiet: Int = 0, vol: Int = 6,
                       connected: Bool = true, listening: Bool = false, mode: Mode = .normal,
                       name: String = "Mochi", classifier: String? = nil) -> Runtime.Status {
        let statuses: [String: SessionSummary.Status] = ["wait": .waiting, "work": .working, "idle": .idle]
        let sessions = rows.map { SessionSummary(agent: $0[0], project: $0[1], status: statuses[$0[2]]!) }
        let wait = sessions.filter { $0.status == .waiting }
        let snapshot = StateSnapshot(
            time: 1_790_000_000, name: name, base: base,
            attn: wait.first.map { StateSnapshot.Attention(agent: $0.agent, project: $0.project, more: wait.count - 1) },
            busy: sessions.filter { $0.status == .working }.count, idle: sessions.filter { $0.status == .idle }.count,
            wait: wait.count, quiet: quiet, vol: vol)
        return Runtime.Status(snapshot: snapshot, sessions: sessions, connected: connected,
                              device: connected ? DeviceStatus(id: "b00p-54fe", fw: "1.0.0") : nil,
                              mode: mode,
                              classifier: classifier ?? (mode == .calm ? "calm@1" : mode == .chatty ? "chatty@1" : "jev:jev-latest"),
                              writer: "apple:26.4", listening: listening)
    }

    static func overviews(_ installer: HookInstaller) -> [(String, AppModel)] {
        [
            ("asleep", model(installer, status: status(base: "asleep"))),
            ("working", model(installer, status: status(sessions: [
                ["codex", "landing", "work"], ["codex", "buddygotchi", "work"],
                ["claude", "jetpack", "work"], ["claude", "notes", "idle"],
            ]))),
            ("needs-you", model(installer, status: status(sessions: [
                ["codex", "landing", "wait"], ["claude", "jetpack", "wait"],
                ["codex", "buddygotchi", "work"], ["claude", "notes", "idle"],
            ], quiet: 8))),
            ("listening", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], listening: true))),
            ("calm", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], mode: .calm))),
            ("mic-refused", {
                let m = model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]]))
                m.talkError = "Allow Boop in System Settings → Privacy & Security → Microphone."
                return m
            }()),
            ("offline", {
                let m = model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                        vol: 0, connected: false))
                m.restartAgents = true
                return m
            }()),
            ("not-running", {
                let m = model(installer, status: nil)
                m.startError = "Another Boop is already running."
                return m
            }()),
            ("waking-up", model(installer, status: nil)),
            ("no-device", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                          connected: false), link: .none)),
            // Every mode chip at once, under the longest kind of name.
            ("all-chips", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], quiet: 12, vol: 0,
                                                          mode: .chatty, name: "Wobblebottom McSnugs"))),
            // Many sessions, a long project, two in one project, and one
            // needing you from a project with no name.
            ("crowded", model(installer, status: status(sessions: [
                ["codex", "", "wait"], ["claude", "jetpack", "work"], ["claude", "jetpack", "work"],
                ["codex", "buddygotchi-landing-page-redesign", "work"], ["claude", "notes", "work"],
                ["codex", "landing", "idle"], ["claude", "dotfiles", "idle"], ["claude", "blog", "idle"],
                ["codex", "scratch", "idle"], ["claude", "archive", "idle"],
            ]))),
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

    /// Every icon on a light and a dark menu bar, as the bar draws it: the
    /// top row at 1× and the bottom at 2×, each pixel blown up to 4×4 or 2×2
    /// so the grid can be judged.
    static func renderIcons(dark: Bool, to dir: URL) {
        let moods: [FaceMood] = [.asleep, .idle, .working, .needsYou, .listening]
        let icon = MenuBarIcon.image(.idle).size
        let pad: CGFloat = 10, gap: CGFloat = 14, row: CGFloat = 24, zoom: CGFloat = 4
        let size = NSSize(width: 2 * pad + CGFloat(moods.count) * icon.width + CGFloat(moods.count - 1) * gap,
                          height: 2 * row)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let bar = NSColor(white: dark ? 0.16 : 0.93, alpha: 1)
        let ink = dark ? NSColor.white : NSColor(white: 0, alpha: 0.85)
        // One strip of icons at `scale` pixels per point, on the bar's colour.
        func strip(_ scale: CGFloat) -> NSBitmapImageRep {
            let rep = bitmap(NSSize(width: size.width, height: row), scale: scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bar.setFill()
            NSRect(origin: .zero, size: rep.size).fill()
            appearance.performAsCurrentDrawingAppearance {
                for (i, mood) in moods.enumerated() {
                    // Whole points, as the status button places it.
                    let rect = NSRect(x: pad + CGFloat(i) * (icon.width + gap), y: ((row - icon.height) / 2).rounded(.down),
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
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let rep = bitmap(size, scale: zoom)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        context?.imageInterpolation = .none
        NSGraphicsContext.current = context
        strip(1).draw(in: NSRect(x: 0, y: row, width: size.width, height: row), from: .zero, operation: .copy,
                      fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        strip(2).draw(in: NSRect(x: 0, y: 0, width: size.width, height: row), from: .zero, operation: .copy,
                      fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        let name = "menubar-\(dark ? "dark" : "light")"
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("snapshots: \(name) has no PNG") }
        do { try png.write(to: dir.appendingPathComponent("\(name).png")) } catch { fail("snapshots: \(error)") }
        print("\(name).png")
    }

    private static func bitmap(_ size: NSSize, scale: CGFloat) -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { fail("snapshots: no icon bitmap") }
        rep.size = size
        return rep
    }
}
