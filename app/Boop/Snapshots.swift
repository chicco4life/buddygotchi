import AppKit
import BoopKit
import SwiftUI

/// `Boop --snapshots DIR`: renders the popover's panes and the menu-bar
/// icons to PNGs, in light and dark, from fixed fixtures, then exits
/// (VERIFICATION.md L0). No runtime, no Bluetooth, no microphone, and the
/// agents' settings it reads are in a throwaway HOME.
@MainActor
enum Snapshots {
    static func run(_ args: Arguments) -> Never {
        guard let dir = args["--snapshots"] else { fail("--snapshots needs a directory") }
        let out = URL(fileURLWithPath: dir)
        checkContrast()
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
                /// The popover on `pane`, tall enough for all of it.
                func shot(_ name: String, _ model: AppModel, pane: Pane) {
                    model.pane = pane
                    render(PopoverView(model: model, maxHeight: 2000), "\(name)-\(dark ? "dark" : "light")", dark: dark, to: out)
                }
                for (name, model) in overviews(installer) { shot("overview-\(name)", model, pane: .overview) }
                let settings = model(installer, status: status(sessions: [["codex", "landing", "work"]]))
                settings.remembered = ["Ships on Fridays.", "Likes tests before lunch."]
                try? installer.install(.claude)
                settings.refreshHooks()
                settings.restartAgents = true
                shot("settings", settings, pane: .settings)
                try? installer.remove(.claude)
                let chatty = model(installer, status: status(mode: .chatty))
                chatty.mode = .chatty
                shot("settings-chatty", chatty, pane: .settings)
                shot("settings-no-hook", model(unbuilt, status: status()), pane: .settings)
                // Normal without Jev's key, the body away and Claude's hooks needing a repair.
                let offline = model(installer, status: status(connected: false, classifier: "chatty@1"))
                offline.hooks[.claude] = .outdated
                shot("settings-offline-nokey", offline, pane: .settings)

                for step in SetupDraft.Step.allCases {
                    let setup = model(installer, status: nil)
                    setup.setup.step = step
                    setup.setup.agents = [.claude]
                    if step.rawValue >= SetupDraft.Step.name.rawValue { setup.setup.name = "Mochi" }
                    shot("setup-\(step.rawValue + 1)-\(step)", setup, pane: .setup)
                }
                let cheeky = model(installer, status: nil)
                cheeky.setup.step = .name
                cheeky.setup.name = "Mochi"
                cheeky.setup.nature = .cheeky
                shot("setup-2-name-cheeky", cheeky, pane: .setup)
                let setup = model(unbuilt, status: nil)
                setup.setup.step = .agents
                setup.setup.agents = [.claude]
                setup.setup.name = "Mochi"
                shot("setup-3-agents-no-hook", setup, pane: .setup)
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
            // Cut as the core cuts it for the device; the popover shows it whole.
            attn: wait.first.map {
                StateSnapshot.Attention(agent: $0.agent, project: StateSnapshot.clip($0.project, marked: true), more: wait.count - 1)
            },
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
                ["codex", "landing-page-redesign-v2", "wait"], ["claude", "jetpack", "wait"],
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
                m.startError = AppModel.startProblem(Runtime.OpenError.locked("/tmp/boop"))
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

    // MARK: Contrast

    /// UX.md §7's contrast rules, checked on every run, in both
    /// appearances: each text tone at least 4.5:1 on everything it sits on
    /// (the paper, a card, the well, its own chip and the needs-you card's
    /// amber wash); the filled buttons' labels 4.5:1 on their fills, pressed
    /// too; the filled button 3:1 on a card, so it outweighs an outlined
    /// one; and the coloured menu-bar icons 3:1 on a light and a dark menu bar.
    static func checkContrast() {
        var pairs: [(String, String, String, Double)] = []
        let tones = [("ink", Palette.inkLight, Palette.inkDark), ("inkSoft", Palette.inkSoftLight, Palette.inkSoftDark),
                     ("amberInk", Palette.amberInkLight, Palette.amberInkDark),
                     ("sageInk", Palette.sageInkLight, Palette.sageInkDark),
                     ("clayInk", Palette.clayInkLight, Palette.clayInkDark)]
        // Each appearance's paper, card and well, and its filled button: fill, pressed fill, label.
        let looks = [("light", Palette.paperLight, Palette.raisedLight, Palette.wellLight,
                      Palette.glass, Palette.glassPressed, Palette.oat),
                     ("dark", Palette.paperDark, Palette.raisedDark, Palette.wellDark,
                      Palette.oat, Palette.oatPressed, Palette.glass)]
        for (i, (look, paper, card, well, fill, pressed, label)) in looks.enumerated() {
            for (name, light, dark) in tones {
                let tone = i == 0 ? light : dark
                pairs += [("\(name) on \(look) paper", tone, paper, 4.5),
                          ("\(name) on a \(look) card", tone, card, 4.5),
                          ("\(name) on the \(look) well", tone, well, 4.5),
                          ("\(name) on its \(look) chip", tone, mix(tone, Theme.chipTint, over: card), 4.5),
                          ("\(name) on the \(look) needs-you card", tone, mix(Palette.amber, Theme.cardTint, over: card), 4.5)]
            }
            pairs += [("a button's label on its \(look) fill", label, fill, 4.5),
                      ("a button's label on its \(look) pressed fill", label, pressed, 4.5),
                      ("a \(look) filled button on a card", fill, card, 3)]
        }
        pairs += [("Send's label", "#FFFFFF", Palette.recordingFill, 4.5),
                  ("Send's label, pressed", "#FFFFFF", Palette.recordingPressed, 4.5),
                  ("needs you on a light menu bar", Palette.menuAmberLight, "#F5F5F5", 3),
                  ("needs you on a dark menu bar", Palette.amber, "#2A2A2A", 3),
                  ("listening on a light menu bar", Palette.recording, "#F5F5F5", 3),
                  ("listening on a dark menu bar", Palette.recording, "#2A2A2A", 3)]
        let low = pairs.compactMap { what, fg, bg, least -> String? in
            let ratio = contrast(fg, bg)
            return ratio < least ? "\(what) is \(String(format: "%.2f", ratio)):1, under \(least):1" : nil
        }
        if !low.isEmpty { fail("snapshots: contrast (UX.md §7): \(low.joined(separator: "; "))") }
        print("contrast: \(pairs.count) pairs pass")
    }

    /// `fg` at `alpha` over `bg`, as SwiftUI's opacity composites it.
    static func mix(_ fg: String, _ alpha: Double, over bg: String) -> String {
        let (f, b) = (NSColor(hex: fg), NSColor(hex: bg))
        let c = { (x: CGFloat, y: CGFloat) in Int(((alpha * Double(x) + (1 - alpha) * Double(y)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(f.redComponent, b.redComponent),
                      c(f.greenComponent, b.greenComponent), c(f.blueComponent, b.blueComponent))
    }

    static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let c = NSColor(hex: hex)
            let lin = { (v: CGFloat) -> Double in
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
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
