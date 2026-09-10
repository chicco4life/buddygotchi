import XCTest
import SwiftUI
@testable import BoopCore

// MARK: - Snapshot / self-verification harness
//
// Renders the REAL SwiftUI views (PopoverView, SettingsView, OnboardingView — no
// reconstructions) in driven engine states to PNGs under /tmp/buddy-snapshots,
// via NSHostingView, which lays out ScrollView content and draws live controls.
// Also exercises the approval "button press" loop end to end. Disabled by
// default (so plain `swift test` / CI stays headless-safe); enable + run:
//
//     mkdir -p /tmp/buddy-snapshots && touch /tmp/buddy-snapshots/.enable
//     swift test --disable-sandbox --filter SnapshotHarnessTests
//
// Open the PNGs (or Read them) to visually verify each state. Only caveat:
// animated views (TimelineView) are captured at a single frame.

@MainActor
final class SnapshotHarnessTests: XCTestCase {

    private let defaults = UserDefaults(suiteName: "BoopTests.snapshots")!

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: "BoopTests.snapshots")
    }

    private let dir = "/tmp/buddy-snapshots"

    override func setUp() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "\(dir)/.enable") && ProcessInfo.processInfo.environment["BOOP_SKIP_SNAPSHOTS"] != "1",
            "snapshot harness disabled — `touch /tmp/buddy-snapshots/.enable` to enable"
        )
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defaults.set(true, forKey: DefaultsKey.setupCompleted)
        defaults.set(Pet.defaultSpecies, forKey: DefaultsKey.buddySpecies)
    }

    func testRenderAll() throws {
        SnapshotRenderer.renderAll(to: dir, defaults: defaults)
        for scene in CompanionScene.all {
            for appearance in ["light", "dark"] {
                for surface in scene.needsPopover ? ["popover"] : ["creature"] {
                    let path = "\(dir)/phase7-\(surface)-\(scene.name)-\(appearance).png"
                    XCTAssertTrue(FileManager.default.fileExists(atPath: path), "Missing scene: " + path)
                }
            }
        }
        XCTAssertEqual(renderState(from: .initial, defaults: defaults, now: 0).state, .asleep)
    }

    // MARK: Helpers

    private func makeEngine() -> BuddyEngine {
        BuddyEngine(config: BuddyConfig(httpPort: 0, staleTimeoutMs: 600_000,
                                        celebrateDurationMs: 4_000, stateDir: "/tmp", approvalMode: false, token: "test-token"), defaults: defaults)
    }

    private func snapshot<V: View>(_ view: V, _ name: String, _ size: CGSize) throws {
        SnapshotRenderer.render(view, name, size, dir, defaults: defaults)
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(name).png"))
        XCTAssertGreaterThan(data.count, 1000, "\(name): PNG suspiciously small")
    }

    private func popover(_ engine: BuddyEngine) -> some View {
        PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults))
    }

    private func onboarding(step: OnboardingStep) -> some View {
        defaults.set(false, forKey: DefaultsKey.setupCompleted)
        defaults.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
        defaults.set("blob", forKey: DefaultsKey.buddySpecies)
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)
        defaults.set(BuddyOutputTarget.thisMac.rawValue, forKey: DefaultsKey.buddyOutput)
        let engine = BuddyEngine(defaults: defaults)
        if step == .done { defaults.set(false, forKey: DefaultsKey.firstCheerShown); engine.firstCheer() }
        return OnboardingView(defaults: defaults, engine: engine, esp32Output: ESP32Output(defaults: defaults), onFinish: {})
    }

    private var popoverIdle: CGSize { CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewHeight) }
    private var popoverPrompt: CGSize { CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewExpandedHeight) }

    // MARK: 1. Popover in each ambient state

    func testPopoverSleep() throws {
        // No sessions → disconnected / sleeping.
        try snapshot(popover(makeEngine()), "popover-1-sleep", popoverIdle)
    }

    func testPopoverBusy() throws {
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/boop")
        e.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        XCTAssertEqual(e.state.pet.state, .busy)
        try snapshot(popover(e), "popover-2-busy", popoverIdle)
    }

    func testPopoverPassivePrompt() throws {
        // Read-only tool card (no Approve/Deny buttons).
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "cursor", cwd: "/Users/dev/boop")
        e.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash",
                        hint: "git push origin main", sessionLabel: "boop")
        XCTAssertEqual(e.state.pet.state, .attention)
        XCTAssertEqual(e.state.prompt?.isApproval, false)
        try snapshot(popover(e), "popover-3-passive-prompt", popoverPrompt)
    }

    // MARK: 3. Passive attention and reminder dismissal

    func testPassiveAttentionSnoozeLoop() throws {
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/boop")
        e.submitRequest(sessionId: "s1", requestId: "r1", tool: "Question", hint: "Which project should I use?", sessionLabel: "boop")
        XCTAssertEqual(e.state.prompt?.isApproval, false)
        try snapshot(popover(e), "popover-4-attention", popoverPrompt)
        e.nudgeDismissed(requestId: "r1")
        XCTAssertEqual(e.state.prompt?.id, "r1", "Snooze does not resolve the request")
        XCTAssertEqual(e.state.creature.nudgeRung, 0)
        try snapshot(popover(e), "popover-5-snoozed", popoverPrompt)
    }

    // MARK: 4. Settings (regression for toggle-alignment fix #4)

    func testSettings() throws {
        let e = makeEngine()
        for section in SettingsSection.sidebar {
            let view = SettingsSectionView(isPresented: .constant(true), engine: e, esp32Output: ESP32Output(defaults: defaults),
                                           serverHealth: nil, section: section).formStyle(.grouped)
            try snapshot(view, "settings-" + section.rawValue, CGSize(width: 520, height: section == .advanced ? 1200 : 650))
        }
    }

    // MARK: 5. Onboarding window steps

    func testOnboardingSteps() throws {
        for step in OnboardingStep.allCases {
            try snapshot(
                onboarding(step: step),
                "onboarding-\(step.rawValue)-\(String(describing: step))",
                CGSize(width: BuddyTheme.onboardingWidth, height: BuddyTheme.onboardingHeight)
            )
        }
    }
}

extension SnapshotHarnessTests {
    func testControlCenterPanes() throws {
        var state = BuddyState.initial
        state.creature.state = .needsYou
        state.creature.card = CreatureCard(id: "settings-regression", tool: "Bash", gloss: "Run the project test suite", stakes: .fine, index: 0, count: 1, isApproval: true)
        let engine = BuddyEngine.preview(state: state, defaults: defaults)
        let navigation = ControlNavigation()
        for pane in ControlPane.allCases {
            navigation.pane = pane
            try snapshot(PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults), navigation: navigation),
                         "control-center-" + pane.rawValue, CGSize(width: 360, height: 590))
        }

    }
}

extension SnapshotHarnessTests {
    func testMenuBarCompactCatalog() throws {
        var state = BuddyState.initial
        state.creature.state = .working
        state.activeSessions = [SessionSnapshot(id: "preview", source: "codex", state: .working, sessionLabel: "buddygotchi")]
        state.growth = GrowthSnapshot(level: 4, xp: 930, xpNext: 270, streak: 5, bestStreak: 9, daysTogether: 18, tasks: 42, today: 86)
        let engine = BuddyEngine.preview(state: state, defaults: defaults)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            let navigation = ControlNavigation()
            func shot(_ name: String, height: CGFloat = 560) {
                SnapshotRenderer.render(PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults), navigation: navigation),
                    "menu-" + name + "-" + suffix, CGSize(width: 360, height: height), dir, defaults: defaults, dark: dark)
            }
            shot("overview", height: 450)
            for count in [6, 10, 12] {
                var many = state
                many.activeSessions = (0..<count).map {
                    SessionSnapshot(id: "session-\($0)", source: "codex", state: .working, sessionLabel: "Project \($0 + 1)")
                }
                let manyEngine = BuddyEngine.preview(state: many, defaults: defaults)
                SnapshotRenderer.render(PopoverView(engine: manyEngine, esp32Output: ESP32Output(defaults: defaults), navigation: ControlNavigation()),
                    "menu-sessions-\(count)-" + suffix, CGSize(width: 360, height: min(450 + CGFloat(min(count, 10) - 3) * 42, max(450, (NSScreen.main?.visibleFrame.height ?? 900) - 40))), dir, defaults: defaults, dark: dark)
            }
            navigation.pane = .settings
            shot("settings-all")
            SnapshotRenderer.render(SettingsSectionView(isPresented: .constant(true), engine: engine,
                esp32Output: ESP32Output(defaults: defaults), serverHealth: nil, section: .all),
                "menu-settings-full-" + suffix, CGSize(width: 360, height: 3300), dir, defaults: defaults, dark: dark)
            for step in OnboardingStep.allCases {
                defaults.set(step.rawValue, forKey: DefaultsKey.onboardingStep)
                SnapshotRenderer.render(OnboardingView(defaults: defaults, engine: engine, esp32Output: ESP32Output(defaults: defaults), compact: true, onFinish: {}),
                    "menu-setup-\(step)-" + suffix, CGSize(width: 360, height: 450), dir, defaults: defaults, dark: dark)
            }
        }
    }
}
