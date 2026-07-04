import AppKit
import SwiftUI

// Headless snapshot renderer: `Buddygotchi --render-snapshots <dir>` renders the
// real SwiftUI surfaces (popover states, settings, onboarding steps, species
// gallery) to PNGs and exits. Mirrors Tests/SnapshotHarnessTests.swift but needs
// no XCTest, so it works on CommandLineTools-only machines and inside scripts.
// TimelineView-driven animation is captured at a single frame.
@MainActor
enum SnapshotRenderer {
    static func renderAll(to dir: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        defaults.set("blob", forKey: DefaultsKey.buddySpecies)

        let idle = CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewHeight)
        let expanded = CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewExpandedHeight)
        let settingsSize = CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.popoverHeight)
        let onboardingSize = CGSize(width: BuddyTheme.onboardingWidth, height: BuddyTheme.onboardingHeight)

        // 1. Popover: sleep (empty state)
        render(popover(makeEngine()), "popover-1-sleep", idle, dir)

        // 2. Popover: busy with activity row
        let busy = makeEngine()
        busy.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/buddygotchi")
        busy.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        busy.activitySignal(sessionId: "s1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift build --product Buddygotchi")
        render(popover(busy), "popover-2-busy", idle, dir)

        // 3. Popover: passive prompt
        let passive = makeEngine()
        passive.sessionStarted(sessionId: "s1", source: "cursor", cwd: "/Users/dev/buddygotchi")
        passive.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "git push origin main", sessionLabel: "buddygotchi")
        render(popover(passive), "popover-3-passive-prompt", expanded, dir)

        // 4. Popover: blocking approval with queue count + error trailer
        let approval = makeEngine()
        approval.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/buddygotchi")
        approval.sessionStarted(sessionId: "s2", source: "codex", cwd: "/Users/dev/landing")
        approval.sessionStarted(sessionId: "s3", source: "cursor", cwd: "/Users/dev/api")
        approval.activitySignal(sessionId: "s3", source: "cursor", signal: .error, tool: "Shell", hint: "npm test")
        Task { _ = await approval.submitApproval(sessionId: "s1", requestId: "rq1", tool: "Bash", hint: "rm -rf build && npm ci", sessionLabel: "buddygotchi", source: "claude-code") }
        Task { _ = await approval.submitApproval(sessionId: "s2", requestId: "rq2", tool: "Write", hint: "src/app/page.tsx", sessionLabel: "landing", source: "codex") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        render(popover(approval), "popover-4-approval-queue-error", expanded, dir)
        approval.resolveAllPendingApprovals(decision: .passthrough)

        // 5. Popover: multi-session list
        let multi = makeEngine()
        multi.sessionStarted(sessionId: "m1", source: "claude-code", cwd: "/Users/dev/buddygotchi")
        multi.activitySignal(sessionId: "m1", source: "claude-code", signal: .keepWorking, tool: "Edit", hint: "PopoverView.swift")
        multi.sessionStarted(sessionId: "m2", source: "codex", cwd: "/Users/dev/landing")
        multi.activitySignal(sessionId: "m2", source: "codex", signal: .keepWorking, tool: "Bash", hint: "npm run build")
        multi.sessionStarted(sessionId: "m3", source: "cursor", cwd: "/Users/dev/api")
        render(popover(multi), "popover-5-multi-session", expanded, dir)

        // 6. Popover: error card
        let errored = makeEngine()
        errored.sessionStarted(sessionId: "e1", source: "codex", cwd: "/Users/dev/landing")
        errored.activitySignal(sessionId: "e1", source: "codex", signal: .startWorking)
        errored.activitySignal(sessionId: "e1", source: "codex", signal: .error, tool: "Bash", hint: "npm test — 3 failures")
        render(popover(errored), "popover-6-error", expanded, dir)

        // 7. Popover: review card (completed)
        let review = makeEngine()
        review.sessionStarted(sessionId: "c1", source: "claude-code", cwd: "/Users/dev/buddygotchi")
        review.activitySignal(sessionId: "c1", source: "claude-code", signal: .startWorking)
        review.activitySignal(sessionId: "c1", source: "claude-code", signal: .keepWorking, tool: "Bash", hint: "swift test")
        review.activitySignal(sessionId: "c1", source: "claude-code", signal: .celebrate)
        render(popover(review), "popover-7-review", expanded, dir)

        // 8. Settings (popover-height viewport + full-height capture of the whole scroll)
        let settingsEngine = makeEngine()
        let settings = SettingsView(isPresented: .constant(true), engine: settingsEngine, esp32Output: ESP32Output(), serverHealth: nil)
        render(settings, "settings", settingsSize, dir)
        var settingsFull = SettingsView(isPresented: .constant(true), engine: makeEngine(), esp32Output: ESP32Output(), serverHealth: nil)
        settingsFull.frameHeight = 1400
        render(settingsFull, "settings-full", CGSize(width: BuddyTheme.popoverWidth, height: 1400), dir)

        // 9. Onboarding steps
        for step in OnboardingStep.allCases {
            defaults.set(false, forKey: DefaultsKey.setupCompleted)
            defaults.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
            defaults.set("Mochi", forKey: DefaultsKey.buddyName)
            defaults.set(BuddyOutputTarget.thisMac.rawValue, forKey: DefaultsKey.buddyOutput)
            let view = OnboardingView(engine: makeEngine(), esp32Output: ESP32Output(), onFinish: {})
            render(view, "onboarding-\(step.rawValue)-\(String(describing: step))", onboardingSize, dir)
        }
        defaults.set(true, forKey: DefaultsKey.setupCompleted)

        // 10. Species gallery
        let gallery = HStack(spacing: 10) {
            ForEach(buddyOrder, id: \.self) { sp in
                VStack(spacing: 4) {
                    PetStageView(petState: .idle, species: sp)
                    Text(sp).font(.buddyMono(11)).foregroundStyle(BuddyTheme.textPrimary)
                }
            }
        }
        .padding(20)
        render(gallery, "species-gallery", CGSize(width: 800, height: 180), dir)

        print("SNAPSHOTS WRITTEN to \(dir)")
    }

    private static func makeEngine() -> BuddyEngine {
        BuddyEngine(config: BuddyConfig(
            httpPort: 0, staleTimeoutMs: 600_000, approvalTimeoutMs: 300_000,
            celebrateDurationMs: 4_000, workStallTimeoutMs: 300_000,
            stateDir: "/tmp", approvalMode: false, token: "snapshot-token"
        ))
    }

    private static func popover(_ engine: BuddyEngine) -> some View {
        PopoverView(engine: engine, esp32Output: ESP32Output())
    }

    private static func render<V: View>(_ view: V, _ name: String, _ size: CGSize, _ dir: String) {
        let root = ZStack { BuddyTheme.night; view }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: AnyView(root))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

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
