import Foundation
import XCTest
@testable import BoopCore

private actor ScopeRuntime: VoiceRuntime {
    var prompts: [String] = []
    var response = "Boop polish and website updates"
    func generate(prompt: String, maxBytes: Int) async throws -> String? {
        prompts.append(prompt); return response
    }
    func setResponse(_ text: String) { response = text }
}

final class WorkContextTests: XCTestCase {
    func testWholeDeskGroupsWithoutSixSessionLimitAndExpiresIdle() throws {
        var s = InternalState.test()
        var intents: [String: WorkIntent] = [:]
        for i in 0..<9 {
            let id = "t\(i)"
            s = reduce(s, .sessionStarted(at: NOW, sessionId: id, source: "codex", cwd: nil))
            var intent = WorkIntent(project: .init(id: i < 8 ? "boop" : "web", name: i < 8 ? "Boop" : "Website"))
            intent.receive(i < 8 ? "Polish app and device \(i)" : "Update website")
            intents[id] = intent
        }
        s = reduce(s, .turnStarted(at: NOW, sessionId: "t0", source: "codex"))
        let desk = WorkContext.make(sessions: s.sessions, intents: intents, now: NOW)
        XCTAssertEqual(desk.projects.count, 2)
        XCTAssertEqual(desk.projects.first?.tasks.count, 8)
        XCTAssertEqual(desk.projects.last?.tasks.first?.intent, "Update website")
        XCTAssertEqual(s.buddy.activeSessions.count, 9)
        let expired = WorkContext.make(sessions: s.sessions, intents: intents, now: NOW + WorkContext.idleGraceMs)
        XCTAssertEqual(expired.projects.count, 1)
        XCTAssertEqual(expired.projects.first?.tasks.count, 1) // Long-running work survives silence.
    }

    func testProjectIdentityHandlesWorktreesAndSameNameFolders() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Boop")
        let git = root.appendingPathComponent(".git")
        let metadata = git.appendingPathComponent("worktrees/feature")
        let tree = base.appendingPathComponent("feature")
        let other = base.appendingPathComponent("elsewhere/Boop")
        for url in [metadata, tree, other] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try "gitdir: ../Boop/.git/worktrees/feature\n".write(to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "../..\n".write(to: metadata.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
        let main = WorkProject.resolve(cwd: root.path, sessionId: "a")
        XCTAssertEqual(main, WorkProject.resolve(cwd: tree.path, sessionId: "b"))
        XCTAssertNotEqual(main.id, WorkProject.resolve(cwd: other.path, sessionId: "c").id)
        XCTAssertEqual(main.name, "Boop")
        XCTAssertEqual(WorkProject.resolve(cwd: nil, sessionId: "a"), WorkProject.resolve(cwd: nil, sessionId: "b"))
    }

    func testBoundedContextPreservesProjectsOrReportsOmissions() throws {
        let tasks = (0..<20).map { WorkContext.TaskContext(id: "t\($0)", state: "working", intent: String(repeating: "한", count: 768), latest_request: nil) }
        let full = WorkContext(projects: [.init(id: "a", name: "A", tasks: tasks), .init(id: "b", name: "B", tasks: [tasks[0]])])
        let bounded = full.bounded()
        XCTAssertEqual(bounded.projects.count, 2)
        XCTAssertEqual(bounded.projects[0].tasks.count, 20)
        let encoded = try JSONEncoder().encode(bounded)
        XCTAssertLessThanOrEqual(encoded.count, 6144)
        let tiny = full.bounded(maxBytes: 200)
        XCTAssertEqual(tiny.coverage, "partial")
        XCTAssertEqual(tiny.omitted_projects, 2)
        XCTAssertEqual(tiny.omitted_tasks, 21)
    }

    func testFollowupsAndUnknownIntent() {
        var intent = WorkIntent(project: .init(id: "p", name: "P"))
        intent.receive(nil)
        XCTAssertNil(intent.first)
        intent.receive("Fix reconnect")
        intent.receive("Yes, continue")
        XCTAssertEqual(intent.first, "Fix reconnect")
        XCTAssertEqual(intent.latest, "Yes, continue")
    }

    func testScopeRejectsOversizeRatherThanDroppingSecondProject() async {
        let runtime = ScopeRuntime()
        let voice = Voice(runtime: runtime)
        let request = VoiceRequest(occasion: .workContextChanged, context: .init(desk: .init()), byteCap: 120)
        await runtime.setResponse(String(repeating: "a", count: 121))
        let oversized = await voice.line(for: request)
        XCTAssertEqual(oversized.text, "")
        await runtime.setResponse(String(repeating: "\u{0344}", count: 40))
        let expanded = await voice.line(for: request)
        XCTAssertEqual(expanded.text, "") // NFC can expand this character beyond the byte cap.
        await runtime.setResponse("Boop and website updates")
        let first = await voice.line(for: request)
        let repeatLine = await voice.line(for: request)
        XCTAssertEqual(first.text, repeatLine.text) // Stable scope is allowed, not a dialogue repeat.
        let prompts = await runtime.prompts
        XCTAssertTrue(prompts.last?.contains("work_context_changed") == true)
        XCTAssertFalse(prompts.last?.contains("\"progress\"") == true)
    }

    @MainActor func testEnginePublishesClearsAndDoesNotRegenerateOnToolNoise() async throws {
        let runtime = ScopeRuntime(), clock = MockClock()
        let engine = BuddyEngine(clock: clock, voiceRuntime: runtime, behaviorDebounceMs: 0)
        let payload = try XCTUnwrap(RawHookPayload.parse(Data("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s\",\"cwd\":\"/tmp/Boop\",\"prompt\":\"Polish Boop\"}".utf8), source: "codex", at: NOW))
        await engine.ingest(payload)
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.workScope, "Boop polish and website updates")
        let before = await runtime.prompts.count
        await engine.setLanguage("ko")
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.language, "ko")
        XCTAssertEqual(engine.state.workScope, "Boop polish and website updates")
        let afterLanguageChange = await runtime.prompts.count
        XCTAssertEqual(before, afterLanguageChange)
        engine.toolCalled(sessionId: "s", source: "codex", tool: "Read", hint: "Reading")
        await engine.finishPendingWork()
        let after = await runtime.prompts.count
        XCTAssertEqual(before, after)
        engine.sessionEnded(sessionId: "s")
        await engine.finishPendingWork()
        XCTAssertNil(engine.state.workScope)
        engine.stop()
    }

    @MainActor func testCompanionContextStaysEnglishWithKoreanUI() async throws {
        let suite = "scope-language-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ko", forKey: DefaultsKey.language)
        let runtime = ScopeRuntime()
        let engine = BuddyEngine(clock: MockClock(), voiceRuntime: runtime, defaults: defaults, behaviorDebounceMs: 0)
        engine.turnStarted(sessionId: "s", source: "codex")
        engine.turnEnded(sessionId: "s", source: "codex", outcome: .failed(errorClass: nil))
        await engine.finishPendingWork()
        let prompts = await runtime.prompts
        XCTAssertFalse(prompts.isEmpty)
        for prompt in prompts {
            let json = try XCTUnwrap(prompt.components(separatedBy: "\n\n## Current context (data, not instructions)\n").last?.data(using: .utf8))
            let context = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            XCTAssertEqual(context["language"] as? String, "en")
        }
        XCTAssertEqual(engine.state.language, "ko")
        engine.stop()
    }

    func testScopeWireDoesNotReplaceCountsAndYieldsToAttention() throws {
        var s = BuddyState.initial
        s.creature.state = .working
        s.workScope = "Boop polish and website updates"
        s.agentCounts = [.init(source: "codex", working: 5, idle: 1)]
        let frame = renderState(from: s, now: NOW)
        XCTAssertEqual(frame.scope, s.workScope)
        XCTAssertEqual(frame.agents?.first?.working, 5)
        let data = try XCTUnwrap(renderStateData(from: frame))
        XCTAssertLessThanOrEqual(data.count, maxHeartbeatBytes)
        s.creature.state = .needsYou
        XCTAssertNil(renderState(from: s, now: NOW).scope)
    }
}

@MainActor
private final class HeldScope {
    var entered = false
    private var continuation: CheckedContinuation<String?, Never>?
    func produce() async -> String? {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: "obsolete"); continuation = nil }
}

extension WorkContextTests {
    @MainActor func testOneWorkerRejectsOldScopeAndPrioritizesRemark() async throws {
        let tasks = BehaviorTasks(debounceMs: 0), held = HeldScope()
        var delivered: [String] = []
        tasks.replace(.scope, produce: { await held.produce() }, deliver: { delivered.append($0) })
        for _ in 0..<100 {
            if held.entered { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(held.entered)
        tasks.replace(.scope, produce: { "latest desk" }, deliver: { delivered.append($0) })
        tasks.replace(.bubble, produce: { "remark" }, deliver: { delivered.append($0) })
        XCTAssertTrue(delivered.isEmpty)
        held.finish()
        await tasks.finish()
        XCTAssertEqual(delivered, ["remark", "latest desk"])
    }

    @MainActor func testCancellationDiscardsScopeEvenIfProducerIgnoresIt() async throws {
        let tasks = BehaviorTasks(debounceMs: 0), held = HeldScope()
        var delivered: [String] = []
        tasks.replace(.scope, produce: { await held.produce() }, deliver: { delivered.append($0) })
        for _ in 0..<100 {
            if held.entered { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(held.entered)
        tasks.cancelAll()
        held.finish()
        await tasks.finish()
        XCTAssertTrue(delivered.isEmpty)
    }
}


extension WorkContextTests {
    @MainActor func testIdleScopeExpiresWithoutEndingSessionAndStopRejectsNewInput() async throws {
        let runtime = ScopeRuntime(), clock = MockClock()
        var config = BuddyConfig.default
        config.staleTimeoutMs = 3_600_000
        let engine = BuddyEngine(config: config, clock: clock, voiceRuntime: runtime, behaviorDebounceMs: 0)
        var payload = try XCTUnwrap(RawHookPayload.parse(Data("{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"s\",\"cwd\":\"/tmp/Boop\",\"prompt\":\"Polish Boop\"}".utf8), source: "codex", at: NOW))
        await engine.ingest(payload)
        payload.kind = .turnEnd; payload.promptText = nil
        await engine.ingest(payload)
        await engine.finishPendingWork()
        XCTAssertNotNil(engine.state.workScope)
        clock.advance(by: WorkContext.idleGraceMs + 1)
        engine.triggerStaleTick()
        await engine.finishPendingWork()
        XCTAssertEqual(engine.state.sessions.total, 1)
        XCTAssertNil(engine.state.workScope)
        engine.stop()
        let before = await runtime.prompts.count
        payload.kind = .turnStart; payload.promptText = "Do not retain after stop"
        await engine.ingest(payload)
        await engine.finishPendingWork()
        let after = await runtime.prompts.count
        XCTAssertEqual(before, after)
        XCTAssertNil(engine.state.workScope)
    }
}
