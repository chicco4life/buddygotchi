import Foundation
import XCTest
@testable import BoopKit

/// Every action wired to recorders.
final class ActionRig {
    var sent: [DeviceMoment] = []
    var quiet: [Int] = []
    var logs: [String] = []
    var allowed = true
    var asked: Input.QuietAsk? = .start
    var actions: [String: Action] = [:]
    let memory: MemoryStore

    init(memory: MemoryStore) {
        self.memory = memory
        let context = ActionContext(
            send: { [unowned self] in self.sent.append($0) },
            mumblesAllowed: { [unowned self] in self.allowed }, setQuiet: { [unowned self] in self.quiet.append($0) },
            quietAsked: { [unowned self] in self.asked },
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

func react(_ feeling: String, word: String? = nil) -> ToolCall {
    var arguments: [String: ToolValue] = ["feeling": .string(feeling)]
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
            for tool in kind.menu { XCTAssertNotNil(rig.actions[tool], tool) }
        }
        let react = rig.actions["react"]!.definition
        XCTAssertEqual(react.parameters.map(\.name), ["feeling", "word"])
        XCTAssertEqual(react.parameters.map(\.role), [.decided, .written])
        XCTAssertEqual(react.parameters[0].kind, .choice(["happy", "excited", "proud", "curious", "hopeful", "annoyed",
                                                          "sad", "sleepy", "smug", "sulky"]))
        XCTAssertEqual(react.parameters[1].kind, .choice(Sounds.vocabulary))
        XCTAssertEqual(Sounds.vocabulary.count, 40)
        XCTAssertEqual(rig.actions["quiet"]!.definition.parameters[0].kind, .number([0, 15, 30, 60, 120]))
        let remember = rig.actions["remember"]!.definition
        XCTAssertEqual(remember.parameters.map(\.role), [.decided, .written])
        XCTAssertEqual(remember.parameters[0].kind, .choice(["today", "about_you", "preference"]))
        XCTAssertTrue(remember.parameters[0].about["today"]!.hasPrefix("Short-term"))
        XCTAssertTrue(remember.parameters[0].about["about_you"]!.hasPrefix("Long-term: a durable fact"))
        // ARCHITECTURE.md §4's limits, by section.
        let text = remember.parameters[1]
        XCTAssertEqual(["today", "about_you", "preference"].map { text.maxLength(["where": .string($0)]) }, [80, 100, 100])
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

    /// BEHAVIORS.md §4: no mumbles in quiet mode or while something needs you.
    func testAMumbleInQuietIsDropped() {
        rig.allowed = false
        XCTAssertEqual(rig.run(react("happy")), .dropped("Boop is quiet right now"))
        XCTAssertEqual(rig.sent, [])
    }

    func testReactDropsWhatItCantDo() {
        let bad: [ToolCall] = [
            react("furious"),
            react("happy", word: "kubernetes"),
            ToolCall("react", ["word": .string("yay")]),
            ToolCall("react", ["feeling": .string("happy"), "voice": .string("silent")]),
            ToolCall("react", ["feeling": .string("happy"), "text": .string("hello there")]),
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

    /// BEHAVIORS.md §3.3: `quiet` runs only the way the last thing you said
    /// asked, whatever the classifier decided: minutes when you asked for
    /// quiet, 0 when you asked it to stop, and nothing otherwise.
    func testQuietRunsOnlyTheWayAsked() {
        rig.asked = nil
        XCTAssertEqual(rig.run(ToolCall("quiet", ["minutes": .number(30)])),
                       .dropped("only when asked to be quiet or to stop"))
        XCTAssertFalse(rig.run(ToolCall("quiet", ["minutes": .number(0)])).isDone)
        rig.asked = .start
        XCTAssertEqual(rig.run(ToolCall("quiet", ["minutes": .number(0)])), .dropped("asked to be quiet, not to stop"))
        XCTAssertTrue(rig.run(ToolCall("quiet", ["minutes": .number(30)])).isDone)
        // "you can talk again" never starts or stretches quiet.
        rig.asked = .end
        for minutes in [15, 30, 60, 120] {
            XCTAssertEqual(rig.run(ToolCall("quiet", ["minutes": .number(minutes)])), .dropped("asked to stop being quiet"))
        }
        XCTAssertEqual(rig.run(ToolCall("quiet", ["minutes": .number(0)])), .done("quiet ended"))
        XCTAssertEqual(rig.quiet, [30, 0])
    }

    func testQuietReachesTheRealCore() {
        let core = CoreRig()
        var asked: Input.QuietAsk? = .start
        let context = ActionContext(send: { _ in }, setQuiet: { _ = core.core.setQuiet(minutes: $0, at: core.now) },
                                    quietAsked: { asked })
        QuietAction(context: context).run(ToolCall("quiet", ["minutes": .number(30)]))
        XCTAssertEqual(core.core.snapshot(at: core.now).quiet, 30)
        // BEHAVIORS.md §3.3: 0 ends it.
        asked = .end
        XCTAssertEqual(QuietAction(context: context).run(ToolCall("quiet", ["minutes": .number(0)])), .done("quiet ended"))
        XCTAssertEqual(core.core.snapshot(at: core.now).quiet, 0)
    }

    func testRememberTodayWritesANote() {
        XCTAssertTrue(rig.run(remember("today", "demo on Thursday")).isDone)
        XCTAssertEqual(memory.store.shortTerm?.notes, ["demo on Thursday"])
        XCTAssertFalse(rig.run(remember("today", String(repeating: "x", count: 81))).isDone)
        XCTAssertFalse(rig.run(remember("today", "")).isDone)
        XCTAssertFalse(rig.run(remember("today", "ran `make test`")).isDone)
        XCTAssertFalse(rig.run(remember("today")).isDone, "no text")
        XCTAssertEqual(memory.store.shortTerm?.notes.count, 1)
        XCTAssertEqual(rig.logs.count, 4)
    }

    /// Durable facts about the person go to long-term memory
    /// (ARCHITECTURE.md §4.2).
    func testRememberAboutYouAndPreferencesAreLongTerm() {
        XCTAssertTrue(rig.run(remember("about_you", "Ships on Fridays.")).isDone)
        XCTAssertTrue(rig.run(remember("preference", "Likes it quiet before 10am.")).isDone)
        XCTAssertFalse(rig.run(remember("secrets", "x")).isDone)
        XCTAssertFalse(rig.run(remember("temperament", "Nosy.")).isDone, "reflection's sections went with the new day")
        XCTAssertFalse(rig.run(remember("about_you", String(repeating: "x", count: 101))).isDone)
        XCTAssertFalse(rig.run(remember("about_you", "ships on fridays")).isDone, "already remembered")
        let lt = memory.store.longTerm!
        XCTAssertEqual(lt.aboutYou, ["Ships on Fridays."])
        XCTAssertEqual(lt.preferences, ["Likes it quiet before 10am."])
        XCTAssertEqual(memory.store.shortTerm?.notes, [], "nothing short-term")
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
        XCTAssertEqual(react("proud", word: "finally").description, #"react(feeling: "proud", word: "finally")"#)
        XCTAssertEqual(remember("today", "demo on Thursday").plain, #"remember(text: "demo on Thursday", where: today)"#)
    }
}
