import XCTest
import SwiftUI
@testable import Buddygotchi

// MARK: - Snapshot / self-verification harness
//
// Renders the REAL SwiftUI views (PopoverView, SettingsView, PetStageView — no
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

    private let dir = "/tmp/buddy-snapshots"

    override func setUp() async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: "\(dir)/.enable"),
            "snapshot harness disabled — `touch /tmp/buddy-snapshots/.enable` to enable"
        )
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        UserDefaults.standard.set(true, forKey: "setupCompleted")
        UserDefaults.standard.set("cat", forKey: "buddySpecies")
    }

    // MARK: Helpers

    private func makeEngine() -> BuddyEngine {
        BuddyEngine(config: BuddyConfig(httpPort: 0, staleTimeoutMs: 600_000,
                                        celebrateDurationMs: 4_000, workStallTimeoutMs: 300_000, stateDir: "/tmp", approvalMode: false))
    }

    private func snapshot<V: View>(_ view: V, _ name: String, _ size: CGSize) throws {
        // Render the REAL view hierarchy via NSHostingView (unlike ImageRenderer,
        // this lays out ScrollView content and draws live controls like switches).
        // Composite over a dark backdrop — the popover chrome the app shows these
        // views inside; the views themselves are transparent. This adds no view
        // content, just the container background.
        let root = ZStack {
            Color(white: 0.11)
            view
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: AnyView(root))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))   // let SwiftUI draw

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                                "\(name): could not make bitmap rep")
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        XCTAssertGreaterThan(png.count, 1000, "\(name): PNG suspiciously small — likely blank")
        print("SNAPSHOT \(name).png  \(png.count)B  \(Int(size.width))x\(Int(size.height))")
    }

    private func popover(_ engine: BuddyEngine) -> some View {
        PopoverView(engine: engine, esp32Output: ESP32Output())
    }

    private var popoverIdle: CGSize { CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewHeight) }
    private var popoverPrompt: CGSize { CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.liveViewExpandedHeight) }

    // MARK: 1. Every species renders (regression for the bufo→cat default + fallback)

    func testSpeciesGallery() throws {
        let gallery = HStack(spacing: 10) {
            ForEach(buddyOrder, id: \.self) { sp in
                VStack(spacing: 4) {
                    PetStageView(petState: .idle, species: sp)
                    Text(sp).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.07))
        try snapshot(gallery, "species-gallery", CGSize(width: 760, height: 170))
    }

    // MARK: 2. Popover in each ambient state

    func testPopoverSleep() throws {
        // No sessions → disconnected / sleeping.
        try snapshot(popover(makeEngine()), "popover-1-sleep", popoverIdle)
    }

    func testPopoverBusy() throws {
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/buddygotchi")
        e.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking)
        XCTAssertEqual(e.state.pet.state, .busy)
        try snapshot(popover(e), "popover-2-busy", popoverIdle)
    }

    func testPopoverPassivePrompt() throws {
        // Read-only tool card (no Approve/Deny buttons).
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "cursor", cwd: "/Users/dev/buddygotchi")
        e.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash",
                        hint: "git push origin main", sessionLabel: "buddygotchi")
        XCTAssertEqual(e.state.pet.state, .attention)
        XCTAssertEqual(e.state.prompt?.isApproval, false)
        try snapshot(popover(e), "popover-3-passive-prompt", popoverPrompt)
    }

    // MARK: 3. Approval "button press" loop (drive → render → press → render)

    func testApprovalButtonLoop() async throws {
        let e = makeEngine()
        e.sessionStarted(sessionId: "s1", source: "claude-code", cwd: "/Users/dev/buddygotchi")
        let reqId = "s1_req"
        let task = Task { await e.submitApproval(sessionId: "s1", requestId: reqId, tool: "Bash",
                                                 hint: "rm -rf build && npm ci", sessionLabel: "buddygotchi",
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
        let view = SettingsView(isPresented: .constant(true), engine: e, esp32Output: ESP32Output(), serverHealth: nil)
        try snapshot(view, "settings", CGSize(width: BuddyTheme.popoverWidth, height: BuddyTheme.popoverHeight))
    }
}
