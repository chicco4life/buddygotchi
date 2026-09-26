import Foundation
import XCTest
@testable import BoopKit

/// Answers from the now section, after an optional delay.
private struct ScriptBrain: TextBrain {
    let id = "script@1"
    var reply: @Sendable (String) async throws -> String
    func complete(system: String, history: [Exchange], user: String, tools: [ToolDefinition],
                  deadline: Duration) async throws -> String {
        try await reply(Prompt.now(in: user))
    }
}

private let face = #"{"calls":[{"tool":"face","name":"happy"}]}"#
private let quiet = #"{"calls":[]}"#

final class ConversationTests: XCTestCase {
    func run(_ rig: HarnessRig, _ triggers: [Trigger]) async -> [Harness.Record] {
        for t in triggers {
            rig.submit(t)
            await rig.settle()
        }
        return rig.snapshot.records
    }

    func testEachCallRepeatsThePreviousRequestAndAddsToIt() async {
        let rig = HarnessRig(brain: FakeBrain { now in now.hasPrefix("tapped") ? face : quiet })
        let r = await run(rig, [trigger(.tap, "tapped · 09:30 Tuesday"),
                                trigger(.event, "turn finished · claude · a · took 12 s · 09:31 Tuesday"),
                                trigger(.talk, "talk · 09:32 Tuesday", words: "hi")])
        XCTAssertEqual(Set(r.map(\.prompt.system)).count, 1)
        XCTAssertEqual(r[0].prompt.history, [])
        XCTAssertTrue(r[0].prompt.user.hasPrefix("## Boop\n\n## Today\n\n--- now ---\n"), "the first message opens with the memory")
        XCTAssertEqual(r[1].prompt.history, [Exchange(user: r[0].prompt.user, answer: face)])
        XCTAssertTrue(r[1].prompt.user.hasPrefix("--- now ---\nturn finished"), "later messages are just the now section")
        XCTAssertEqual(r[2].prompt.history, r[1].prompt.history + [Exchange(user: r[1].prompt.user, answer: quiet)])
        XCTAssertEqual(r[2].prompt.user, "--- now ---\ntalk · 09:32 Tuesday\nthey said: \"hi\"")
    }

    func testTheAnswerKeepsOnlyWhatRan() async {
        let rig = HarnessRig(brain: FakeBrain { _ in #"{"calls":[{"tool":"face","name":"happy"},{"tool":"quiet","minutes":30}]}"# })
        let r = await run(rig, [trigger(.tap, "tapped · 09:30 Tuesday"), trigger(.tap, "tapped · 09:31 Tuesday")])
        XCTAssertEqual(r[1].prompt.history.map(\.answer), [face])
    }

    /// HARNESS.md §4: a change to the opening starts over.
    func testAMemoryChangeStartsOver() async {
        let rig = HarnessRig(brain: FakeBrain { _ in quiet })
        var r = await run(rig, [trigger(.tap, "tapped · 09:30 Tuesday"), trigger(.tap, "tapped · 09:31 Tuesday")])
        XCTAssertEqual(r[1].prompt.history.count, 1)
        rig.home.sync { rig.memory.shortTerm = "## Today\n09:31 claude · a · finished (40 s)\n" }
        r = await run(rig, [trigger(.tap, "tapped · 09:32 Tuesday")])
        XCTAssertEqual(r[2].prompt.history, [])
        XCTAssertTrue(r[2].prompt.user.contains("finished (40 s)"))
        XCTAssertEqual(rig.home.sync { rig.harness.conversation.restarts }, 1)
    }

    func testAFailedAnswerStartsOverAndACancelledOneChangesNothing() async {
        let rig = HarnessRig(brain: ScriptBrain { now in
            if now.contains("09:31") { throw BrainError("offline") }
            if now.contains("09:40") { try await Task.sleep(for: .milliseconds(300)) }
            return now.hasPrefix("talk") ? quiet : #"{"calls":[{"tool":"face","name":"sulky"}]}"#
        })
        var r = await run(rig, [trigger(.tap, "tapped · 09:30 Tuesday"), trigger(.tap, "tapped · 09:31 Tuesday"),
                                trigger(.tap, "tapped · 09:32 Tuesday"), trigger(.tap, "tapped · 09:33 Tuesday")])
        XCTAssertEqual(r.map(\.prompt.history.count), [0, 1, 0, 1])
        XCTAssertEqual(r[1].dropped, "offline")

        // A talk cancels a running call, which then adds nothing.
        rig.submit(trigger(.event, "turn started · claude · a · 09:40 Tuesday"))
        try? await Task.sleep(for: .milliseconds(50))
        rig.submit(trigger(.talk, "talk · 09:40 Tuesday", words: "hush"))
        await rig.settle()
        r = rig.snapshot.records
        XCTAssertEqual(r[4].dropped, "cancelled by talk")
        XCTAssertEqual(r[5].prompt.history.count, 2)
        XCTAssertEqual(r[5].prompt.history.last?.user, r[3].prompt.user)
    }

    func testALateAnswerOrOneFromAnEarlierConversationAddsNothing() {
        let rig = HarnessRig(brain: FakeBrain { _ in quiet })
        let h = rig.harness!
        rig.home.sync {
            let (call, _, generation) = h.prepare(trigger(.tap, "tapped · 09:30 Tuesday"))
            let late = Harness.Record(trigger: trigger(.tap, "tapped · 09:30 Tuesday"), brain: "fake@1", prompt: call.prompt,
                                      tools: [], raw: nil, dropped: "late: no answer within 3000 ms", ran: [], latencyMs: 3000)
            h.remember(late, limits: [], generation: generation!)
            XCTAssertEqual(h.conversation.turns, [])
            XCTAssertEqual(h.conversation.generation, generation)
            var answered = late
            answered.raw = quiet
            answered.dropped = nil
            h.conversation.restart()
            h.remember(answered, limits: [], generation: generation!)
            XCTAssertEqual(h.conversation.turns, [])
        }
    }

    /// HARNESS.md §4: at most 4 earlier exchanges.
    func testItHoldsAtMostFourExchangesThenStartsOver() async {
        let rig = HarnessRig(brain: FakeBrain { _ in quiet })
        var triggers: [Trigger] = []
        for i in 0..<7 { triggers.append(trigger(.tap, "tapped · 09:3\(i) Tuesday")) }
        let r = await run(rig, triggers)
        XCTAssertEqual(r.map(\.prompt.history.count), [0, 1, 2, 3, 4, 0, 1])
        XCTAssertTrue(r[5].prompt.user.hasPrefix("## Boop"))
    }

    /// HARNESS.md §4: a request stays under 5,000 estimated tokens.
    func testTheBudgetStartsOverInsteadOfSliding() async {
        let rig = HarnessRig(brain: FakeBrain { _ in quiet }, conversation: Conversation(maxExchanges: 100))
        let words = String(repeating: "blah ", count: 600)
        var triggers: [Trigger] = []
        for i in 0..<16 { triggers.append(trigger(.talk, "talk · 10:\(10 + i) Tuesday", words: words)) }
        let r = await run(rig, triggers)
        let counts = r.map(\.prompt.history.count)
        XCTAssertEqual(counts.first, 0)
        // Grows by one each call, then drops to nothing: never a shifted window.
        for (a, b) in zip(counts, counts.dropFirst()) { XCTAssertTrue(b == a + 1 || b == 0, "\(counts)") }
        XCTAssertTrue(counts.dropFirst().contains(0), "\(counts)")
        for record in r {
            XCTAssertLessThanOrEqual(Conversation.tokens(record.prompt, tools: rig.harness.offered(.talk).map(\.definition)),
                                     Conversation.budget)
        }
        for record in r where record.prompt.history.isEmpty { XCTAssertTrue(record.prompt.user.hasPrefix("## Boop")) }
    }

    func testReflectionIsACallOnItsOwn() async {
        let rig = HarnessRig(brain: FakeBrain { _ in quiet })
        let r = await run(rig, [trigger(.tap, "tapped · 09:30 Tuesday"), trigger(.reflect, "reflect · yesterday 2026-10-14"),
                                trigger(.tap, "tapped · 09:31 Tuesday")])
        XCTAssertEqual(r[1].prompt.history, [])
        XCTAssertEqual(r[1].tools, [])
        XCTAssertEqual(r[2].prompt.history.map(\.user), [r[0].prompt.user])
    }
}
