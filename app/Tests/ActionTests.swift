import Foundation
import XCTest
@testable import BoopKit

/// Every action wired to recorders.
final class ActionRig {
    var sent: [DeviceMoment] = []
    var quiet: [Int] = []
    var logs: [String] = []
    var allowed = true
    var actions: [String: Action] = [:]
    let memory: MemoryStore

    init(memory: MemoryStore) {
        self.memory = memory
        let context = ActionContext(
            send: { [unowned self] in self.sent.append($0) }, mood: { Mood() },
            mumblesAllowed: { [unowned self] in self.allowed }, setQuiet: { [unowned self] in self.quiet.append($0) },
            today: { "2026-10-15" }, log: { [unowned self] in self.logs.append($0) })
        for action in Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 0x7f3a)), memory: memory) {
            actions[action.name] = action
        }
    }

    @discardableResult
    func run(_ call: ToolCall) -> ActionOutcome {
        guard let action = actions[call.name] else { return .dropped("no such action") }
        return action.run(call)
    }

    var face: FaceAction { actions["face"] as! FaceAction }
}

final class ActionTests: XCTestCase {
    var memory: MemoryRig!
    var rig: ActionRig!

    override func setUpWithError() throws {
        memory = try MemoryRig()
        rig = ActionRig(memory: memory.store)
    }

    func testThereAreEightActionsEachWithItsDefinition() {
        XCTAssertEqual(Set(rig.actions.keys),
                       ["say", "face", "quiet", "note", "remember", "forget", "temperament", "moment"])
        for kind in [Trigger.Kind.event, .tap, .talk, .reflect] {
            for tool in kind.tools { XCTAssertNotNil(rig.actions[tool], tool) }
        }
        let say = rig.actions["say"]!.definition.json
        XCTAssertTrue(say.hasPrefix(#"{"name":"say","description":"Mumble. Pick a feeling; add one word only if it helps.","parameters":{"feeling":{"enum":["happy","excited","proud","curious","hopeful","annoyed","sad","sleepy"]},"word":{"enum":["tests","build""#))
        XCTAssertTrue(say.hasSuffix(#""what"],"optional":true}}}"#))
        XCTAssertEqual(rig.actions["quiet"]!.definition.json,
                       #"{"name":"quiet","description":"Stop mumbling for a while, when asked to.","parameters":{"minutes":{"enum":[15,30,60,120]}}}"#)
        XCTAssertTrue(rig.actions["note"]!.definition.json.contains(#""text":{"type":"string","maxLength":80}"#))
    }

    /// The tools offered for the biggest trigger fit the 400-token budget
    /// (HARNESS.md §4), at about four bytes a token.
    func testToolDefinitionsFitTheirBudget() {
        for kind in [Trigger.Kind.event, .tap, .talk, .reflect] {
            let bytes = kind.tools.map { rig.actions[$0]!.definition.json.utf8.count }.reduce(0, +)
            XCTAssertLessThanOrEqual(bytes, 1600, "\(kind)")
        }
    }

    func testSaySendsAMumbleWithItsFace() throws {
        let outcome = rig.run(ToolCall("say", ["feeling": .string("proud"), "word": .string("finally")]))
        XCTAssertTrue(outcome.isDone)
        let moment = try XCTUnwrap(rig.sent.last)
        XCTAssertEqual(moment.anim, "proud")
        XCTAssertEqual(moment.say?.word, "finally")
        XCTAssertEqual(moment.say?.tune, .lift)
        XCTAssertTrue(moment.jsonLine.utf8.count <= 512)
        rig.run(ToolCall("say", ["feeling": .string("sleepy")]))
        XCTAssertEqual(rig.sent.last?.anim, "sleepy")
        XCTAssertNil(rig.sent.last?.say?.word)
    }

    func testSayDropsWhatItCantSay() {
        let bad: [ToolCall] = [
            ToolCall("say", ["feeling": .string("furious")]),
            ToolCall("say", ["feeling": .string("happy"), "word": .string("kubernetes")]),
            ToolCall("say", ["word": .string("yay")]),
            ToolCall("say", ["feeling": .string("happy"), "text": .string("hello there")]),
            ToolCall("say", ["feeling": .number(3)]),
        ]
        for call in bad {
            if case .done = rig.run(call) { XCTFail("ran \(call)") }
        }
        XCTAssertEqual(rig.sent, [])
        XCTAssertEqual(rig.logs.count, bad.count)
        // HARNESS.md §8: the reason names the argument, never its value.
        XCTAssertEqual(rig.logs[1], "say: dropped: word isn't one of its choices")
        for line in rig.logs { XCTAssertFalse(line.contains("kubernetes") || line.contains("hello there"), line) }
    }

    func testSayIsSilentWhenMumblesArent() {
        rig.allowed = false
        XCTAssertEqual(rig.run(ToolCall("say", ["feeling": .string("happy")])), .dropped("Boop is quiet right now"))
        XCTAssertEqual(rig.sent, [])
        XCTAssertEqual(rig.logs.count, 1)
    }

    func testFacePicksOnlyFacesButRulesPlayAnything() {
        XCTAssertTrue(rig.run(ToolCall("face", ["name": .string("side_eye")])).isDone)
        XCTAssertEqual(rig.sent.last, DeviceMoment(anim: "side_eye"))
        XCTAssertFalse(rig.run(ToolCall("face", ["name": .string("cheer")])).isDone)  // a rule's animation
        XCTAssertFalse(rig.run(ToolCall("face", ["name": .string("dance")])).isDone)
        XCTAssertTrue(rig.face.play("cheer", size: 3).isDone)
        XCTAssertEqual(rig.sent.last, DeviceMoment(anim: "cheer", size: 3))
        XCTAssertFalse(rig.face.play("dance", size: 1).isDone)
        XCTAssertFalse(rig.face.play("cheer", size: 4).isDone)
        XCTAssertEqual(rig.sent.count, 2)
        XCTAssertEqual(rig.logs.count, 4)
    }

    func testFaceKnowsTheDevicesAnimations() {
        // firmware/src/render/anim.cpp's names, less "none".
        XCTAssertEqual(FaceAction.anims.count, 20)
        XCTAssertTrue(Set(SayAction.faces.values).isSubset(of: FaceAction.anims))
    }

    func testQuietTellsTheCore() {
        XCTAssertTrue(rig.run(ToolCall("quiet", ["minutes": .number(60)])).isDone)
        XCTAssertTrue(rig.run(ToolCall("quiet", ["minutes": .string("30")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("quiet", ["minutes": .number(600)])).isDone)
        XCTAssertFalse(rig.run(ToolCall("quiet", [:])).isDone)
        XCTAssertEqual(rig.quiet, [60, 30])
    }

    func testQuietReachesTheRealCore() {
        let core = CoreRig()
        let context = ActionContext(send: { _ in }, setQuiet: { _ = core.core.setQuiet(minutes: $0, at: core.now) },
                                    today: { "2026-10-14" })
        QuietAction(context: context).run(ToolCall("quiet", ["minutes": .number(30)]))
        XCTAssertEqual(core.core.snapshot(at: core.now).quiet, 30)
    }

    func testNoteWritesToday() {
        XCTAssertTrue(rig.run(ToolCall("note", ["text": .string("ships on Fridays")])).isDone)
        XCTAssertEqual(memory.store.shortTerm?.notes, ["ships on Fridays"])
        XCTAssertFalse(rig.run(ToolCall("note", ["text": .string(String(repeating: "x", count: 81))])).isDone)
        XCTAssertFalse(rig.run(ToolCall("note", ["text": .string("")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("note", ["text": .string("ran `make test`")])).isDone)
        XCTAssertEqual(memory.store.shortTerm?.notes.count, 1)
        XCTAssertEqual(rig.logs.count, 3)
    }

    func testReflectionActions() {
        XCTAssertTrue(rig.run(ToolCall("remember", ["text": .string("Ships on Fridays."), "kind": .string("about_you")])).isDone)
        XCTAssertTrue(rig.run(ToolCall("remember", ["text": .string("Likes it quiet."), "kind": .string("preference")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("remember", ["text": .string("x"), "kind": .string("secret")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("remember", ["text": .string("Works with Bob.")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("forget", ["text": .string("likes it quiet")])).isDone)
        XCTAssertEqual(rig.actions["forget"]!.definition.parameters[0].kind, .choice(["Ships on Fridays.", "Likes it quiet."]))
        XCTAssertTrue(rig.run(ToolCall("forget", ["text": .string("Likes it quiet.")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("forget", ["text": .string("Likes it quiet.")])).isDone)
        XCTAssertTrue(rig.run(ToolCall("temperament", ["text": .string("Trusts Codex more than it used to.")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("temperament", ["text": .string("Gets huffy about flaky tests.")])).isDone)
        XCTAssertTrue(rig.run(ToolCall("moment", ["text": .string("first all-nighter together")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("moment", ["text": .string("another one")])).isDone)
        let lt = memory.store.longTerm!
        XCTAssertEqual(lt.aboutYou, ["Ships on Fridays."])
        XCTAssertEqual(lt.preferences, [])
        XCTAssertEqual(lt.temperament, ["Trusts Codex more than it used to."])
        XCTAssertEqual(lt.moments.map(\.date), ["2026-10-15"])
        XCTAssertEqual(rig.logs.count, 6)
        for line in rig.logs { XCTAssertTrue(line.contains(": dropped: "), line) }
        // The name refusal doesn't repeat the name: it's logged (HARNESS.md §8).
        XCTAssertFalse(rig.run(ToolCall("remember", ["text": .string("Works with Bob."), "kind": .string("about_you")])).isDone)
        XCTAssertEqual(rig.logs.last, "remember: dropped: looks like someone's name")
        XCTAssertFalse(rig.logs.contains { $0.contains("Bob") })
    }

    func testACallToTheWrongActionIsDropped() {
        XCTAssertEqual(rig.actions["say"]!.run(ToolCall("face", ["name": .string("happy")])), .dropped("sent to say"))
    }

    func testToolCallsReadNaturally() {
        XCTAssertEqual(ToolCall("say", ["word": .string("finally"), "feeling": .string("proud")]).description,
                       #"say(feeling: "proud", word: "finally")"#)
    }
}
