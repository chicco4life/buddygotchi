import Foundation
import XCTest
@testable import BoopCore

/// System E at the MCP boundary: protocol shape, tool dispatch, the enforced
/// invariants that live above the reducer (S5 sanitation, S6 rate floor,
/// S1 suppression feedback), and pet-memory persistence.
final class MCPServerTests: XCTestCase {

    @MainActor
    private final class RecordingMemoryStore: PetMemoryStoring {
        var stored: PetMemory?
        var saveCount = 0
        func load() -> PetMemory? { stored }
        func save(_ memory: PetMemory) {
            stored = memory
            saveCount += 1
        }
    }

    @MainActor
    private func makeEngine(store: (any PetMemoryStoring)? = nil) -> (BuddyEngine, MockClock) {
        let clock = MockClock()
        let config = BuddyConfig(
            httpPort: 0,
            staleTimeoutMs: 600_000,
            celebrateDurationMs: 4_000,
            workStallTimeoutMs: 300_000,
            stateDir: "/tmp",
            approvalMode: false,
            token: "test-token"
        )
        return (BuddyEngine(config: config, clock: clock, memoryStore: store), clock)
    }

    @MainActor
    private func call(_ engine: BuddyEngine, tool: String, args: [String: Any], agentId: String = "claude-code") async -> [String: Any]? {
        await handleMCPMessage(
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call",
             "params": ["name": tool, "arguments": args] as [String: Any]],
            agentId: agentId,
            engine: engine
        )
    }

    private func toolText(_ response: [String: Any]?) -> String {
        let result = response?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    private func isToolError(_ response: [String: Any]?) -> Bool {
        ((response?["result"] as? [String: Any])?["isError"] as? Bool) == true
    }

    // MARK: - Protocol shape

    @MainActor
    func testInitializeHandshake() async {
        let (engine, _) = makeEngine()
        let response = await handleMCPMessage(
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["protocolVersion": "2025-03-26"]],
            agentId: "claude-code",
            engine: engine
        )
        let result = response?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-03-26")
        let instructions = result?["instructions"] as? String ?? ""
        XCTAssertTrue(instructions.contains("sparingly"))
        // Personality-neutral on purpose — no prescribed vibe.
        XCTAssertFalse(instructions.lowercased().contains("quirky"))
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "boop")
    }

    @MainActor
    func testToolsListExposesTheFullSurface() async {
        let (engine, _) = makeEngine()
        let response = await handleMCPMessage(
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            agentId: "claude-code",
            engine: engine
        )
        let tools = ((response?["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }),
                       ["report_effort", "introduce", "express", "say"])
    }

    @MainActor
    func testNotificationGetsNoResponse() async {
        let (engine, _) = makeEngine()
        let response = await handleMCPMessage(
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            agentId: "claude-code",
            engine: engine
        )
        XCTAssertNil(response)
    }

    @MainActor
    func testUnknownMethodErrors() async {
        let (engine, _) = makeEngine()
        let response = await handleMCPMessage(
            ["jsonrpc": "2.0", "id": 3, "method": "resources/list"],
            agentId: "claude-code",
            engine: engine
        )
        let error = response?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
    }

    // MARK: - report_effort

    @MainActor
    func testReportEffortWithoutSessionSaysSo() async {
        let (engine, _) = makeEngine()
        let response = await call(engine, tool: "report_effort", args: ["level": "hard"])
        XCTAssertTrue(toolText(response).contains("No live session"))
    }

    @MainActor
    func testReportEffortReachesTheSession() async {
        let (engine, _) = makeEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.activitySignal(sessionId: "s1", source: "claude-code", signal: .startWorking, tool: "Bash", hint: "x")
        let response = await call(engine, tool: "report_effort", args: ["level": "grinding"])
        XCTAssertFalse(isToolError(response))
        XCTAssertEqual(engine.state.effortTier, .grinding)
    }

    @MainActor
    func testReportEffortRejectsUnknownLevel() async {
        let (engine, _) = makeEngine()
        let response = await call(engine, tool: "report_effort", args: ["level": "impossible"])
        XCTAssertTrue(isToolError(response))
    }

    // MARK: - express / say

    @MainActor
    func testExpressShowsOverlay() async {
        let (engine, _) = makeEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        let response = await call(engine, tool: "express", args: ["emotion": "sheepish", "motion": "tilt"])
        XCTAssertEqual(toolText(response), "The pet showed your expression.")
        XCTAssertEqual(engine.state.agentOverlay?.emotion, "sheepish")
        XCTAssertEqual(engine.state.agentOverlay?.motion, "tilt")
        XCTAssertEqual(engine.state.agentOverlay?.agentId, "claude-code")
    }

    @MainActor
    func testExpressRejectsOffVocabularyEmotion() async {
        let (engine, _) = makeEngine()
        let response = await call(engine, tool: "express", args: ["emotion": "malicious-grin"])
        XCTAssertTrue(isToolError(response))
        XCTAssertNil(engine.state.agentOverlay)
    }

    @MainActor
    func testExpressSuppressedWhileApprovalPending() async {
        let (engine, _) = makeEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        engine.submitRequest(sessionId: "s1", requestId: "r1", tool: "Bash", hint: "rm -rf /", sessionLabel: nil)
        let response = await call(engine, tool: "express", args: ["emotion": "happy"])
        XCTAssertTrue(toolText(response).contains("deferred"))
        XCTAssertNil(engine.state.agentOverlay)
    }

    @MainActor
    func testExpressRateFloorBetweenExpressions() async {
        let (engine, clock) = makeEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        _ = await call(engine, tool: "express", args: ["emotion": "happy"])
        clock.advance(by: 10_000)
        let second = await call(engine, tool: "express", args: ["emotion": "proud"])
        XCTAssertTrue(toolText(second).contains("Too soon"))
        // The first expression still owns the overlay.
        XCTAssertEqual(engine.state.agentOverlay?.emotion, "happy")

        clock.advance(by: PetTuning.agentExpressMinGapMs)
        let third = await call(engine, tool: "express", args: ["emotion": "proud"])
        XCTAssertEqual(toolText(third), "The pet showed your expression.")
    }

    @MainActor
    func testSaySanitizesAndCaps() async {
        let (engine, _) = makeEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        let noisy = "hi\u{07}\u{1B}[31m there, this line is far longer than forty bytes"
        let response = await call(engine, tool: "say", args: ["text": noisy, "delivery": "deadpan"])
        XCTAssertFalse(isToolError(response))
        let say = engine.state.agentOverlay?.say ?? ""
        XCTAssertLessThanOrEqual(say.utf8.count, PetTuning.sayMaxBytes)
        XCTAssertNil(say.unicodeScalars.first(where: { CharacterSet.controlCharacters.contains($0) }))
        XCTAssertEqual(engine.state.agentOverlay?.delivery, "deadpan")
    }

    @MainActor
    func testSayRejectsAllControlText() async {
        let (engine, _) = makeEngine()
        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        let response = await call(engine, tool: "say", args: ["text": "\u{07}\u{1B}\u{00}"])
        XCTAssertTrue(isToolError(response))
        XCTAssertNil(engine.state.agentOverlay)
    }

    // MARK: - introduce

    @MainActor
    func testIntroduceRemembersReturningAgents() async {
        let (engine, _) = makeEngine()
        let first = await call(engine, tool: "introduce", args: ["color": "sky", "signature_emote": "zen", "greeting": "hello!"])
        XCTAssertTrue(toolText(first).contains("Nice to meet you"))
        let second = await call(engine, tool: "introduce", args: [:])
        XCTAssertTrue(toolText(second).contains("visit #2"))
        XCTAssertEqual(engine.petMemory.agents["claude-code"]?.color, "sky")
    }

    @MainActor
    func testIntroduceRejectsOffPaletteColor() async {
        let (engine, _) = makeEngine()
        let response = await call(engine, tool: "introduce", args: ["color": "#ff0000"])
        XCTAssertTrue(isToolError(response))
    }

    // MARK: - Real HTTP transport

    /// Boots the real Hummingbird server and drives /mcp over an actual
    /// socket: auth (401 without the token), the initialize handshake, and a
    /// tools/call whose effect lands in engine state. This is the closest a
    /// headless run gets to a live agent connection.
    @MainActor
    func testMCPOverRealHTTP() async throws {
        let (engine, _) = makeEngine()
        let port = Int.random(in: 33000..<59000)
        let config = BuddyConfig(
            httpPort: port,
            staleTimeoutMs: 600_000,
            celebrateDurationMs: 4_000,
            workStallTimeoutMs: 300_000,
            stateDir: "/tmp",
            approvalMode: false,
            token: "test-token"
        )
        let app = buildHookServer(engine: engine, config: config)
        let serverTask = Task { try await app.runService() }
        defer { serverTask.cancel() }

        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!
        let healthz = URL(string: "http://127.0.0.1:\(port)/healthz")!
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (try? await URLSession.shared.data(from: healthz)) != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        func post(_ body: [String: Any], token: String?, agent: String? = "claude-code") async throws -> (Int, [String: Any]?) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token { request.setValue(token, forHTTPHeaderField: "X-Boop-Token") }
            if let agent { request.setValue(agent, forHTTPHeaderField: "X-Boop-Agent") }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        // No token, no entry — the expression channel is not anonymous.
        let (unauthorized, _) = try await post(["jsonrpc": "2.0", "id": 0, "method": "ping"], token: nil)
        XCTAssertEqual(unauthorized, 401)

        let (initStatus, initBody) = try await post(
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["protocolVersion": "2025-06-18"]],
            token: "test-token"
        )
        XCTAssertEqual(initStatus, 200)
        XCTAssertNotNil((initBody?["result"] as? [String: Any])?["instructions"])

        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        let (_, expressBody) = try await post(
            ["jsonrpc": "2.0", "id": 2, "method": "tools/call",
             "params": ["name": "express", "arguments": ["emotion": "triumphant"]] as [String: Any]],
            token: "test-token"
        )
        let text = (((expressBody?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertEqual(text, "The pet showed your expression.")
        XCTAssertEqual(engine.state.agentOverlay?.emotion, "triumphant")
        XCTAssertEqual(engine.state.agentOverlay?.agentId, "claude-code")
    }

    // MARK: - Persistence

    @MainActor
    func testMemoryStoreSeedsAndSaves() {
        let store = RecordingMemoryStore()
        var seeded = PetMemory.empty
        seeded.lifetimeSessions = 7
        seeded.lastSeenAt = 500_000
        store.stored = seeded

        let (engine, _) = makeEngine(store: store)
        engine.start()
        defer { engine.stop() }
        XCTAssertEqual(engine.petMemory.lifetimeSessions, 7)

        engine.sessionStarted(sessionId: "s1", source: "claude-code", cwd: nil)
        XCTAssertEqual(store.stored?.lifetimeSessions, 8)
        XCTAssertGreaterThan(store.saveCount, 0)
    }

    func testFilePetMemoryStoreRoundTrips() async {
        let dir = NSTemporaryDirectory() + "boop-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        await MainActor.run {
            let store = FilePetMemoryStore(stateDir: dir)
            var memory = PetMemory.empty
            memory.lifetimeSessions = 3
            memory.hourHistogram[9] = 12
            memory.agents["claude-code"] = AgentIdentity(color: "sky", signatureEmote: "zen", greeting: "hi", visits: 4, lastSeenAt: 1)
            store.save(memory)
            XCTAssertEqual(store.load(), memory)
        }

        await MainActor.run {
            // A corrupt file costs the memory, never the launch.
            let path = dir + "/pet-memory.json"
            try? Data("not json".utf8).write(to: URL(fileURLWithPath: path))
            XCTAssertNil(FilePetMemoryStore(stateDir: dir).load())
        }
    }
}
