import Foundation
import XCTest
@testable import BoopKit

/// Every action wired to recorders.
final class ActionRig {
    var sent: [DeviceMoment] = []
    var quiet: [Int] = []
    var logs: [String] = []
    var allowed = true
    var asked = true
    var actions: [String: Action] = [:]
    let memory: MemoryStore

    init(memory: MemoryStore) {
        self.memory = memory
        let context = ActionContext(
            send: { [unowned self] in self.sent.append($0) },
            mumblesAllowed: { [unowned self] in self.allowed }, setQuiet: { [unowned self] in self.quiet.append($0) },
            quietAsked: { [unowned self] in self.asked }, today: { "2026-10-15" },
            log: { [unowned self] in self.logs.append($0) })
        for action in Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 0x7f3a)), memory: memory) {
            actions[action.name] = action
        }
    }

    @discardableResult
    func run(_ call: ToolCall) -> ActionOutcome {
        guard let action = actions[call.name] else { return .dropped("no such action") }
        return action.run(call)
    }

    var react: ReactAction { actions["react"] as! ReactAction }
}

func react(_ feeling: String, _ voice: String = "mumble", word: String? = nil) -> ToolCall {
    var arguments: [String: ToolValue] = ["feeling": .string(feeling), "voice": .string(voice)]
    if let word { arguments["word"] = .string(word) }
    return ToolCall("react", arguments)
}

func remember(_ place: String, _ text: String? = nil) -> ToolCall {
    var arguments: [String: ToolValue] = ["where": .string(place)]
    if let text { arguments["text"] = .string(text) }
    return ToolCall("remember", arguments)
}

final class ActionTests: XCTestCase {
    var memory: MemoryRig!
    var rig: ActionRig!

    override func setUpWithError() throws {
        memory = try MemoryRig()
        rig = ActionRig(memory: memory.store)
    }

    /// HARNESS.md §5: three outputs, each argument with its role.
    func testThereAreThreeOutputs() {
        XCTAssertEqual(Set(rig.actions.keys), ["react", "quiet", "remember"])
        for kind in Input.Kind.allCases {
            for item in kind.menu { XCTAssertNotNil(rig.actions[item.tool], item.tool) }
        }
        let react = rig.actions["react"]!.definition
        XCTAssertEqual(react.parameters.map(\.name), ["feeling", "voice", "word"])
        XCTAssertEqual(react.parameters.map(\.role), [.decided, .decided, .writtenWhen("voice", is: "mumble")])
        XCTAssertEqual(react.parameters[0].kind, .choice(["happy", "excited", "proud", "curious", "hopeful", "annoyed",
                                                          "sad", "sleepy", "smug", "sulky"]))
        XCTAssertEqual(react.parameters[2].kind, .choice(Sounds.vocabulary))
        XCTAssertEqual(Sounds.vocabulary.count, 40)
        XCTAssertEqual(rig.actions["quiet"]!.definition.parameters[0].kind, .number([15, 30, 60, 120]))
        let remember = rig.actions["remember"]!.definition
        XCTAssertEqual(remember.parameters.map(\.role), [.decided, .written])
        XCTAssertEqual(remember.parameters[0].kind, .choice(["today", "about_you", "preference", "temperament", "moment"]))
        // ARCHITECTURE.md §4's limits, by section.
        let text = remember.parameters[1]
        XCTAssertEqual(["today", "about_you", "preference", "temperament", "moment"].map {
            text.maxLength(["where": .string($0)])
        }, [80, 100, 100, 120, 80])
    }

    /// A mumble is a moment with only `say`: it plays over whatever face is
    /// showing (PROTOCOL.md §3).
    func testAMumbleCarriesItsWordAndNoFace() throws {
        XCTAssertTrue(rig.run(react("proud", word: "finally")).isDone)
        let moment = try XCTUnwrap(rig.sent.last)
        XCTAssertNil(moment.anim)
        XCTAssertEqual(moment.say?.word, "finally")
        XCTAssertEqual(moment.say?.tune, .lift)
        XCTAssertTrue(moment.jsonLine.utf8.count <= 512)
        XCTAssertFalse(moment.jsonLine.contains("anim"))
        rig.run(react("sleepy"))
        XCTAssertNil(rig.sent.last?.anim)
        XCTAssertNil(rig.sent.last?.say?.word)
        XCTAssertNotNil(rig.sent.last?.say)
    }

    /// The ten feelings choose the voice; smug and sulky borrow one.
    func testEachFeelingMumblesInItsVoice() {
        for (name, _, _) in ReactAction.feelings {
            XCTAssertTrue(rig.run(react(name)).isDone, name)
            XCTAssertEqual(rig.sent.last?.anim, nil, name)
        }
        rig.run(react("smug"))
        XCTAssertEqual(rig.sent.last?.say?.tune, .lift, "smug mumbles like proud")
        rig.run(react("sulky"))
        XCTAssertEqual(rig.sent.last?.say?.tune, .down, "sulky mumbles like sad")
    }

    /// The feelings' faces are parked (FUTURE.md): silent shows nothing.
    func testSilentShowsNothing() {
        XCTAssertEqual(rig.run(react("sulky", "silent", word: "nope")), .done("sulky, silent: Boop has no face for it in v1"))
        XCTAssertEqual(rig.sent, [])
    }

    /// BEHAVIORS.md §6: no mumbles in quiet mode or while something needs you.
    func testAMumbleInQuietIsDropped() {
        rig.allowed = false
        XCTAssertEqual(rig.run(react("happy")), .dropped("Boop is quiet right now"))
        XCTAssertEqual(rig.sent, [])
    }

    func testReactDropsWhatItCantDo() {
        let bad: [ToolCall] = [
            react("furious"),
            react("happy", word: "kubernetes"),
            ToolCall("react", ["voice": .string("mumble")]),
            react("happy", "shout"),
            ToolCall("react", ["feeling": .string("happy"), "voice": .string("mumble"), "text": .string("hello there")]),
        ]
        for call in bad {
            if case .done = rig.run(call) { XCTFail("ran \(call)") }
        }
        XCTAssertEqual(rig.sent, [])
        XCTAssertEqual(rig.logs.count, bad.count)
        // HARNESS.md §8: the reason names the argument, never its value.
        XCTAssertEqual(rig.logs[1], "react: dropped: word isn't one of its choices")
        for line in rig.logs { XCTAssertFalse(line.contains("kubernetes") || line.contains("hello there"), line) }
    }

    /// BEHAVIORS.md §5: the rules play only the three kept animations.
    func testRulesPlayOnlyTheKeptAnimations() {
        XCTAssertEqual(ReactAction.anims, ["cheer", "wiggle", "listening"])
        for anim in ReactAction.anims {
            XCTAssertTrue(rig.react.play(anim).isDone, anim)
            XCTAssertEqual(rig.sent.last, DeviceMoment(anim: anim))
        }
        let removed = ["nod", "thinking", "shrug", "dance", "stretch", "oops", "side_eye", "gobble", "levelup", "happy", "proud"]
        for anim in removed {
            XCTAssertFalse(rig.react.play(anim).isDone, anim)
        }
        XCTAssertEqual(rig.sent.count, 3)
        XCTAssertEqual(rig.logs.count, removed.count)
        // The core's `.endListening`: the empty moment.
        XCTAssertTrue(rig.react.endListening().isDone)
        XCTAssertEqual(rig.sent.last, DeviceMoment.empty)
    }

    func testQuietTellsTheCore() {
        XCTAssertTrue(rig.run(ToolCall("quiet", ["minutes": .number(60)])).isDone)
        XCTAssertTrue(rig.run(ToolCall("quiet", ["minutes": .string("30")])).isDone)
        XCTAssertFalse(rig.run(ToolCall("quiet", ["minutes": .number(600)])).isDone)
        XCTAssertFalse(rig.run(ToolCall("quiet", [:])).isDone)
        XCTAssertEqual(rig.quiet, [60, 30])
    }

    /// BEHAVIORS.md §3.3: `quiet` runs only when the last thing you said
    /// asked for quiet, whatever the classifier decided.
    func testQuietRunsOnlyWhenAsked() {
        rig.asked = false
        XCTAssertEqual(rig.run(ToolCall("quiet", ["minutes": .number(30)])), .dropped("only when asked to be quiet"))
        XCTAssertEqual(rig.quiet, [])
        rig.asked = true
        XCTAssertTrue(rig.run(ToolCall("quiet", ["minutes": .number(30)])).isDone)
        XCTAssertEqual(rig.quiet, [30])
    }

    func testQuietReachesTheRealCore() {
        let core = CoreRig()
        let context = ActionContext(send: { _ in }, setQuiet: { _ = core.core.setQuiet(minutes: $0, at: core.now) },
                                    today: { "2026-10-14" })
        QuietAction(context: context).run(ToolCall("quiet", ["minutes": .number(30)]))
        XCTAssertEqual(core.core.snapshot(at: core.now).quiet, 30)
    }

    func testRememberTodayWritesANote() {
        XCTAssertTrue(rig.run(remember("today", "ships on Fridays")).isDone)
        XCTAssertEqual(memory.store.shortTerm?.notes, ["ships on Fridays"])
        XCTAssertFalse(rig.run(remember("today", String(repeating: "x", count: 81))).isDone)
        XCTAssertFalse(rig.run(remember("today", "")).isDone)
        XCTAssertFalse(rig.run(remember("today", "ran `make test`")).isDone)
        XCTAssertFalse(rig.run(remember("today")).isDone, "no text")
        XCTAssertEqual(memory.store.shortTerm?.notes.count, 1)
        XCTAssertEqual(rig.logs.count, 4)
    }

    func testRememberEachLongTermSection() {
        XCTAssertTrue(rig.run(remember("about_you", "Ships on Fridays.")).isDone)
        XCTAssertTrue(rig.run(remember("preference", "Likes it quiet.")).isDone)
        XCTAssertFalse(rig.run(remember("secrets", "x")).isDone)
        XCTAssertFalse(rig.run(remember("about_you", String(repeating: "x", count: 101))).isDone)
        XCTAssertTrue(rig.run(remember("temperament", "Trusts Codex more than it used to.")).isDone)
        XCTAssertFalse(rig.run(remember("temperament", "Gets huffy about flaky tests.")).isDone, "once a day")
        XCTAssertTrue(rig.run(remember("moment", "first all-nighter together")).isDone)
        XCTAssertFalse(rig.run(remember("moment", "another one")).isDone, "one a day")
        let lt = memory.store.longTerm!
        XCTAssertEqual(lt.aboutYou, ["Ships on Fridays."])
        XCTAssertEqual(lt.preferences, ["Likes it quiet."])
        XCTAssertEqual(lt.temperament, ["Trusts Codex more than it used to."])
        XCTAssertEqual(lt.moments.map(\.date), ["2026-10-15"])
        XCTAssertEqual(rig.logs.count, 4)
        for line in rig.logs { XCTAssertTrue(line.contains(": dropped: "), line) }
        // The name refusal doesn't repeat the name: it's logged (HARNESS.md §8).
        XCTAssertFalse(rig.run(remember("about_you", "Works with Bob.")).isDone)
        XCTAssertEqual(rig.logs.last, "remember: dropped: looks like someone's name")
        XCTAssertFalse(rig.logs.contains { $0.contains("Bob") })
    }

    func testACallToTheWrongActionIsDropped() {
        XCTAssertEqual(rig.actions["react"]!.run(ToolCall("quiet", ["minutes": .number(15)])), .dropped("sent to react"))
    }

    func testToolCallsReadNaturally() {
        XCTAssertEqual(react("proud", word: "finally").description, #"react(feeling: "proud", voice: "mumble", word: "finally")"#)
        XCTAssertEqual(remember("today", "demo on Thursday").plain, #"remember(text: "demo on Thursday", where: today)"#)
    }
}
