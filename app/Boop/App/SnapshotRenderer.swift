import AppKit
import SwiftUI

// Headless snapshot renderer: `Boop --render-snapshots <dir>` renders the
// real SwiftUI surfaces (popover states, settings, onboarding steps, species
// gallery) to PNGs and exits. Mirrors Tests/SnapshotHarnessTests.swift but needs
// no XCTest, so it works on CommandLineTools-only machines and inside scripts.
// TimelineView-driven animation is captured at a single frame.
@MainActor
enum SnapshotRenderer {
    @MainActor private final class Surface {
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        init() { window.contentView = host }
    }
    private static let surface = Surface()

    static var expectedRenderCount: Int {
        let companionPerAppearance = CompanionScene.all.count + 2 + 2 + SettingsSection.sidebar.count + OnboardingStep.allCases.count
        let other = 7 + OnboardingStep.allCases.count + FirmwareUpdater.snapshotStates.count + 1 + 4
        return 2 * companionPerAppearance + other + 2 // one cream share card per language
    }

    static func renderAll(to dir: String, defaults: UserDefaults) {
        func makeEngine() -> BuddyEngine { Self.makeEngine(defaults: defaults) }
        func render<V: View>(_ view: V, _ name: String, _ size: CGSize, _ dir: String) {
            Self.render(view, name, size, dir, defaults: defaults)
        }
        _ = NSApplication.shared
        // --render-snapshots returns before BoopApp.main(), so AppDelegate's
        // applicationDidFinishLaunching never runs and Geist never registers.
        // Without this every PNG is drawn in the system fallback face and the
        // text metrics do not match the shipping app.
        BuddyResources.registerFonts()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        defaults.set("blob", forKey: DefaultsKey.buddySpecies)
        // Every fixture that reads a default must find a known value, not
        // whatever a previous run left behind. The onboarding and stress sections
        // both write buddyName, so settings rendered differently depending on
        // which of them ran last.
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)

        let idle = CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewHeight)
        let expanded = CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewExpandedHeight)
        let onboardingSize = CGSize(width: BuddyTheme.onboardingWidth, height: BuddyTheme.onboardingHeight)

        renderCompanionScenes(to: dir, defaults: defaults)

        // 1. Popover: sleep (empty state)
        render(popover(makeEngine(), defaults: defaults), "popover-1-sleep", idle, dir)

        // 2. Popover: busy with activity row
        let busy = makeEngine()
        busy.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/boop")
        busy.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        busy.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift build --product Boop")
        render(popover(busy, defaults: defaults), "popover-2-busy", idle, dir)

        // 3. Popover: passive prompt
        let passive = makeEngine()
        passive.sessionStarted(sessionId: "s1", source: "cursor", cwd: "/Users/dev/boop")
        passive.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "git push origin main", sessionLabel: "boop")
        render(popover(passive, defaults: defaults), "popover-3-passive-prompt", expanded, dir)

        // 4. Popover: blocking approval with queue count + error trailer
        let approval = makeEngine()
        approval.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/boop")
        approval.sessionStarted(sessionId: "s2", source: "codex", cwd: "/Users/dev/landing")
        approval.sessionStarted(sessionId: "s3", source: "cursor", cwd: "/Users/dev/api")
        approval.activitySignal(sessionId: "s3", source: "cursor", signal: .error, tool: "Shell", hint: "npm test")
        Task { _ = await approval.submitApproval(sessionId: "s1", requestId: "rq1", tool: "Bash", hint: "rm -rf build && npm ci", sessionLabel: "boop", source: "claude-code") }
        Task { _ = await approval.submitApproval(sessionId: "s2", requestId: "rq2", tool: "Write", hint: "src/app/page.tsx", sessionLabel: "landing", source: "codex") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        render(popover(approval, defaults: defaults), "popover-4-approval-queue-error", expanded, dir)
        approval.resolveAllPendingApprovals(decision: .passthrough)

        // 5. Popover: multi-session list
        let multi = makeEngine()
        multi.sessionStarted(sessionId: "m1", source: "claude-code", cwd: "/Users/dev/boop")
        multi.activitySignal(sessionId: "m1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "PopoverView.swift")
        multi.sessionStarted(sessionId: "m2", source: "codex", cwd: "/Users/dev/landing")
        multi.activitySignal(sessionId: "m2", source: "codex", signal: .keepWorking, tool: "Bash", hint: "npm run build")
        multi.sessionStarted(sessionId: "m3", source: "cursor", cwd: "/Users/dev/api")
        render(popover(multi, defaults: defaults), "popover-5-multi-session", expanded, dir)

        // 6. Popover: error card
        let errored = makeEngine()
        errored.sessionStarted(sessionId: "e1", source: "codex", cwd: "/Users/dev/landing")
        errored.activitySignal(sessionId: "e1", source: "codex", signal: .startWorking)
        errored.activitySignal(sessionId: "e1", source: "codex", signal: .error, tool: "Bash", hint: "npm test — 3 failures")
        render(popover(errored, defaults: defaults), "popover-6-error", expanded, dir)

        // 7. Popover: review card (completed)
        let review = makeEngine()
        review.sessionStarted(sessionId: "c1", source: "claude-code", cwd: "/Users/dev/boop")
        review.activitySignal(sessionId: "c1", source: "claude-code", signal: .startWorking)
        review.activitySignal(sessionId: "c1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        review.activitySignal(sessionId: "c1", source: "claude-code", signal: .celebrate)
        render(popover(review, defaults: defaults), "popover-7-review", expanded, dir)

        // 9. Onboarding steps
        for step in OnboardingStep.allCases {
            defaults.set(false, forKey: DefaultsKey.setupCompleted)
            defaults.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
            defaults.set("Mochi", forKey: DefaultsKey.buddyName)
            defaults.set(BuddyOutputTarget.thisMac.rawValue, forKey: DefaultsKey.buddyOutput)
            let onboardingEngine = makeEngine()
            if step == .done { defaults.set(false, forKey: DefaultsKey.firstCheerShown); onboardingEngine.firstCheer() }
            let view = OnboardingView(defaults: defaults, engine: onboardingEngine, esp32Output: ESP32Output(defaults: defaults), onFinish: {})
            render(view, "onboarding-\(step.rawValue)-\(String(describing: step))", onboardingSize, dir)
        }
        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        // Don't leave fixture state behind — a persisted step would make
        // "Run setup again" resume mid-flow on the next real launch.
        defaults.removeObject(forKey: DefaultsKey.onboardingStep)

        // 10. Firmware sheet. It is presented with .sheet, so it never appeared in
        // any harness, and it is the densest surface after settings.
        for (name, state) in FirmwareUpdater.snapshotStates {
            let updater = FirmwareUpdater.preview(state: state)
            let view = FirmwareUpdateView(updater: updater, isPresented: .constant(true))
            render(view, "firmware-\(name)", CGSize(width: BuddyTheme.popoverWidth, height: 320), dir)
        }

        // 11. Menu bar icon, on both appearances. The status item inherits the
        // system appearance rather than Boop's, so it is the one surface that has
        // to survive a light menu bar and a dark one.
        renderStatusIcons(dir)

        // 12. Stress: pathological text in a 320pt panel. Agents really do send
        // 300-character shell commands and 12-segment paths, and a repo checked
        // out under a long directory name gives every row a long session label.
        // These are the fixtures that catch overflow, so they render at a tall
        // canvas — anything that clips or pushes a control off the edge is a bug.
        let stressSize = CGSize(width: BuddyTheme.popoverWidth, height: 420)
        defaults.set("Bartholomew Fitzgerald-Wellington III", forKey: DefaultsKey.buddyName)

        let longHint = makeEngine()
        longHint.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/very-long-monorepo-name")
        Task {
            _ = await longHint.submitApproval(
                sessionId: "s1", requestId: "rq1",
                tool: "mcp__filesystem__read_text_file_with_a_long_name",
                hint: "find . -type f -name '*.swift' -not -path './.build/*' -exec sed -i '' 's/BuddyTheme.textPrimary/BuddyTheme.ink/g' {} + && swift build --product Boop 2>&1 | grep -c 'error:'",
                sessionLabel: "very-long-monorepo-name", source: "claude-code"
            )
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        render(popover(longHint, defaults: defaults), "stress-1-long-approval", stressSize, dir)
        longHint.resolveAllPendingApprovals(decision: .passthrough)

        let longPath = makeEngine()
        longPath.sessionStarted(sessionId: "s1", source: "cursor", cwd: "/Users/dev/api")
        longPath.submitRequest(
            sessionId: "s1", requestId: "r1", tool: "Write",
            hint: "/Users/dev/api/packages/backend/src/modules/authentication/providers/oauth2/strategies/GoogleWorkspaceStrategy.ts",
            sessionLabel: "backend-authentication-service"
        )
        render(popover(longPath, defaults: defaults), "stress-2-long-path", stressSize, dir)

        let longError = makeEngine()
        longError.sessionStarted(sessionId: "e1", source: "codex", cwd: "/Users/dev/landing")
        longError.activitySignal(sessionId: "e1", source: "codex", signal: .startWorking)
        longError.activitySignal(
            sessionId: "e1", source: "codex", signal: .error,
            tool: "npm run build --workspace=@boop/landing",
            hint: "Type error: Property 'buddySpecies' does not exist on type 'RenderState'. Did you mean 'species'? at src/lib/heartbeat.ts:42:17"
        )
        render(popover(longError, defaults: defaults), "stress-3-long-error", stressSize, dir)

        let manySessions = makeEngine()
        for (i, src) in ["claude-code", "codex", "cursor", "claude-code", "codex"].enumerated() {
            manySessions.sessionStarted(sessionId: "x\(i)", source: src, cwd: "/Users/dev/service-\(i)")
            manySessions.activitySignal(
                sessionId: "x\(i)", source: src, signal: .keepWorking,
                tool: "Bash", hint: "pnpm --filter @acme/service-\(i) test --coverage"
            )
        }
        render(popover(manySessions, defaults: defaults), "stress-4-many-sessions", stressSize, dir)
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)

        print("SNAPSHOTS WRITTEN to \(dir)")
    }

    /// Draws every creature state in both menu bar appearances at 4x.
    private static func renderStatusIcons(_ dir: String) {
        let scale: CGFloat = 4
        let cell: CGFloat = 18 * scale
        let states = CreatureState.allCases
        let size = NSSize(width: cell * CGFloat(states.count), height: cell * 2)

        let sheet = NSImage(size: size, flipped: false) { _ in
            for (row, appearance) in [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)].enumerated() {
                let backdrop: NSColor = row == 0 ? .white : NSColor(white: 0.13, alpha: 1)
                backdrop.setFill()
                NSRect(x: 0, y: CGFloat(1 - row) * cell, width: size.width, height: cell).fill()

                for (col, state) in states.enumerated() {
                    // statusIcon reads labelColor, so it has to be drawn inside the
                    // appearance it will live in.
                    appearance?.performAsCurrentDrawingAppearance {
                        var creature = Creature.initial; creature.state = state
                        let icon = DesktopOutput.statusIcon(for: creature)
                        icon.draw(
                            in: NSRect(x: CGFloat(col) * cell, y: CGFloat(1 - row) * cell, width: cell, height: cell),
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 1
                        )
                    }
                }
            }
            return true
        }

        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: "\(dir)/menubar-icons.png"))
        print("SNAPSHOT menubar-icons.png \(png.count)B \(Int(size.width))x\(Int(size.height))")
    }

    private static func makeEngine(defaults: UserDefaults) -> BuddyEngine {
        BuddyEngine(config: BuddyConfig(
            httpPort: 0, staleTimeoutMs: 600_000, approvalTimeoutMs: 300_000,
            celebrateDurationMs: 4_000, workStallTimeoutMs: 300_000,
            stateDir: "/tmp", approvalMode: false, token: "snapshot-token"
        ), defaults: defaults)
    }

    private static func popover(_ engine: BuddyEngine, defaults: UserDefaults) -> some View {
        PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults))
    }

    private static func renderCompanionScenes(to dir: String, defaults: UserDefaults) {
        for language in ["en", "ko"] {
            var creature = Creature.initial; creature.state = .done; creature.cheer = .cheer
            let card = ShareCard(creature: creature, cosmetic: EquippedCosmetic(), name: language == "ko" ? "보리" : "Mochi", level: 12, streak: 7,
                                 line: VoiceBanks.lines(language: language, occasion: "share", register: .wry)[0], language: language)
            if let png = try? card.pngData() {
                try? png.write(to: URL(fileURLWithPath: dir + "/share-" + language + ".png"))
            }
        }
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            func shot<V: View>(_ view: V, _ name: String, width: CGFloat = 360, height: CGFloat = 640) {
                render(view, "phase7-" + name + "-" + suffix, CGSize(width: width, height: height), dir, defaults: defaults, dark: dark)
            }
            for scene in CompanionScene.all {
                guard scene.needsPopover else {
                    // Overlay moments (boop, greet) are over in 900 ms, so the
                    // default 1.25 s freeze lands after the heart has gone. Catch
                    // them mid-gesture instead, or the sheet documents nothing.
                    let at = scene.creature.overlay != nil ? 0.45 : 1.25
                    shot(CreatureView(creature: scene.creature, cosmetic: scene.cosmetic, frozen: true, frozenTime: at), "creature-" + scene.name, height: 240)
                    continue
                }
                var state = BuddyState.initial; state.creature = scene.creature; state.cosmetic = scene.cosmetic
                let engine = BuddyEngine.preview(state: state, defaults: defaults)
                shot(PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults)), "popover-" + scene.name)
            }
            let recap = Recap(line: "good day", paragraph: "Green at last. A little progress became a good day.", turns: 14, tasks: 3, biggest: "hardWonPass")
            var recapState = BuddyState.initial; recapState.recap = recap
            shot(PopoverView(engine: BuddyEngine.preview(state: recapState, defaults: defaults), esp32Output: ESP32Output(defaults: defaults)), "popover-recap")
            shot(RecapView(language: "en", recap: recap), "recap", height: 240)
            for count in [0, 3] {
                let lines = (0..<count).map { ProfileLine(id: $0, line: ["You often work in the morning.", "Tests are part of your routine.", "You have been working on Boop."][$0], source: "rules", confidence: 1, createdAt: 1_780_000_000_000) }
                shot(ProfilePage(language: "en", lines: lines), "profile-\(count)", width: 520, height: 540)
            }
            let engine = BuddyEngine(defaults: defaults)
            for section in SettingsSection.sidebar {
                shot(SettingsSectionView(isPresented: .constant(true), engine: engine, esp32Output: ESP32Output(defaults: defaults),
                                         serverHealth: nil, section: section).formStyle(.grouped),
                     "settings-" + section.rawValue, width: 520, height: section == .advanced ? 1200 : 650)
            }
            for step in OnboardingStep.allCases {
                defaults.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
                let onboardingEngine = makeEngine(defaults: defaults)
                if step == .done { defaults.set(false, forKey: DefaultsKey.firstCheerShown); onboardingEngine.firstCheer() }
                shot(OnboardingView(defaults: defaults, engine: onboardingEngine, esp32Output: ESP32Output(defaults: defaults), onFinish: {}), "onboarding-\(step)", width: BuddyTheme.onboardingWidth, height: BuddyTheme.onboardingHeight)
            }
            defaults.removeObject(forKey: DefaultsKey.onboardingStep)
        }
    }

    static func render<V: View>(_ view: V, _ name: String, _ size: CGSize, _ dir: String, defaults: UserDefaults, dark: Bool = false) {
        // A trailing spacer pins content to the top whatever the view's own
        // min-height alignment does; popovers size to content in the real app.
        let root = ZStack(alignment: .top) { BuddyTheme.windowBackground; VStack(spacing: 0) { view; Spacer(minLength: 0) } }.id(name)
            .frame(width: size.width, height: size.height, alignment: .top)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.snapshotFrozen, true)
            .environment(\.controlActiveState, .key)
            .defaultAppStorage(defaults)

        let host = surface.host
        let window = surface.window
        host.rootView = AnyView(root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: size)

        window.setContentSize(size)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded()
        // Native split-view and list rows finish their layout on the next turn.
        // Drain those updates before capturing the AppKit-backed controls.
        let layoutDeadline = Date.now.addingTimeInterval(0.05)
        while Date.now < layoutDeadline {
            _ = RunLoop.main.run(mode: .default, before: layoutDeadline)
        }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.orderOut(nil) }

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("SNAPSHOT FAILED \(name): no bitmap rep")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("SNAPSHOT FAILED \(name): no png")
            return
        }
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        print("SNAPSHOT \(name).png \(png.count)B \(Int(size.width))x\(Int(size.height))")
    }
}
