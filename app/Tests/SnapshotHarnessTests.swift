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
                                        celebrateDurationMs: 4_000, workStallTimeoutMs: 300_000, stateDir: "/tmp", approvalMode: false, token: "test-token"), defaults: defaults)
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

    // MARK: 3. Approval "button press" loop (drive → render → press → render)

    func testApprovalButtonLoop() async throws {
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/boop")
        let reqId = "s1_req"
        let task = Task { await e.submitApproval(sessionId: "s1", requestId: reqId, tool: "Bash",
                                                 hint: "rm -rf build && npm ci", sessionLabel: "boop",
                                                 source: "claude-code") }
        await Task.yield()

        // Card with Approve/Deny buttons is showing.
        XCTAssertEqual(e.state.prompt?.isApproval, true)
        XCTAssertEqual(e.state.pet.state, .attention)
        try snapshot(popover(e), "popover-4-approval", popoverPrompt)

        // "Press Approve" — exactly what the button's action calls.
        e.resolveApproval(requestId: reqId, decision: .allow)
        let decision = await task.value

        XCTAssertEqual(decision, .allow)
        XCTAssertNil(e.state.prompt, "card should clear after approving")
        XCTAssertEqual(e.state.pet.state, .busy, "approving resumes work")
        try snapshot(popover(e), "popover-5-after-approve", popoverIdle)
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
        let engine = makeEngine()
        let navigation = ControlNavigation()
        for pane in ControlPane.allCases {
            navigation.pane = pane
            try snapshot(PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults), navigation: navigation),
                         "control-center-" + pane.rawValue, CGSize(width: 760, height: 620))
        }
        navigation.settingsCategory = .displays
        try snapshot(PopoverView(engine: engine, esp32Output: ESP32Output(defaults: defaults), navigation: navigation),
                     "control-center-appearance", CGSize(width: 760, height: 620))
    }
}
