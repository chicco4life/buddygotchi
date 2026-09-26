import Foundation
import XCTest
@testable import BoopKit

/// HARNESS.md §4: one append-only transcript, and a window onto it.
final class TranscriptTests: XCTestCase {
    func said(_ n: Int) -> Input { input(.said, words: "hi \(n)", at: Double(n)) }

    /// At most 8 inputs; a 9th starts the window again from the last 2, and
    /// nothing already in the transcript changes.
    func testTheWindowHoldsEightInputsThenKeepsTheLastTwo() {
        let t = Transcript()
        var before: [Transcript.Entry] = []
        var sizes: [Int] = []
        for n in 1...12 {
            t.begin(said(n))
            t.append(.ran(react("happy"), .done("ok")))
            XCTAssertEqual(Array(t.entries.prefix(before.count)), before, "append-only")
            before = t.entries
            sizes.append(t.inputs)
        }
        XCTAssertEqual(sizes, [1, 2, 3, 4, 5, 6, 7, 8, 3, 4, 5, 6])
        XCTAssertEqual(t.restarts, 1)
        XCTAssertEqual(Transcript.windowInputs, 8)
        XCTAssertEqual(Transcript.keptInputs, 2)
        guard case .input(let first) = t.window.first else {
            XCTFail("the window starts with an input")
            return
        }
        XCTAssertEqual(first.words, "hi 7", "the last two before the 9th: 7 and 8")
    }

    /// Asides don't count as inputs, and a new day starts its own window.
    func testAsidesDontCountAndANewDayStartsAfresh() {
        let t = Transcript()
        t.begin(said(1))
        for n in 0..<20 { t.append(.aside("tapped", ts: Int64(n))) }
        XCTAssertEqual(t.inputs, 1)
        t.begin(input(.newDay))
        XCTAssertEqual(t.window, [.input(input(.newDay))])
        XCTAssertEqual(t.restarts, 1)
        t.begin(said(2))
        XCTAssertEqual(t.inputs, 2, "the day's inputs follow its reflection")
    }

    func testTheInputsRulesFollowIt() {
        let t = Transcript()
        let finished = input(.agentFinished, tookMs: 60_000, rules: "cheer")
        t.begin(finished)
        XCTAssertEqual(t.entries, [.input(finished), .rules("cheer")])
    }

    /// What a language model reads (HARNESS.md §4).
    func testTheWindowAsText() {
        let window: [Transcript.Entry] = [
            .input(input(.agentFinished, tookMs: 1_080_000, rules: "cheer")), .rules("cheer"),
            .decided(by: "rules@2", [react("proud")], evidence: "done, over a minute"),
            .wrote(by: "apple:27.0", ["react.word": "finally"]),
            .ran(react("proud", word: "finally"), .done("ok")),
            .aside("tapped · 14:07 Tuesday: Boop wiggled", ts: 0),
            .input(input(.said, words: "remember \"the\"\ndemo")),
            .decided(by: "rules@2", [react("happy"), remember("today")], evidence: nil),
            .writeFailed(by: "apple:27.0", "offline"),
            .ran(react("happy"), .done("ok")), .ran(remember("today"), .dropped("nothing was written")),
            .input(input(.agentStarted)), .dropped("late: no answer within 5000 ms"),
        ]
        XCTAssertEqual(Transcript.text(window), """
            agent finished · done · claude · jetpack · took 18 min · 14:05 Tuesday
              rules: cheer
              decided: react(feeling: proud, voice: mumble)
              wrote: react.word = finally
              ran: react(feeling: proud, voice: mumble, word: finally)
            tapped · 14:07 Tuesday: Boop wiggled
            you said · 14:05 Tuesday
              they said: "remember 'the' demo"
              decided: react(feeling: happy, voice: mumble), remember(where: today)
              wrote: nothing
              ran: react(feeling: happy, voice: mumble)
              ran: remember(where: today) (dropped)
            agent started · claude · jetpack · 14:05 Tuesday
              dropped: late: no answer within 5000 ms
            """)
        let groups = Transcript.groups(window)
        XCTAssertEqual(groups.map(\.did), [[react("proud", word: "finally")], nil, [react("happy")], []])
        XCTAssertEqual(groups[0].rules, "cheer")
    }
}

/// HARNESS.md §3: the menu per input, and the check on Stage 1's answer.
final class MenuTests: XCTestCase {
    func definitions() throws -> [ToolDefinition] {
        let memory = try MemoryRig()
        let context = ActionContext(send: { _ in }, today: { "2026-10-14" })
        return Actions.all(context: context, voice: Voice(dialect: Dialect(seed: 1)), memory: memory.store).map(\.definition)
    }

    func testEachInputsMenu() throws {
        let d = try definitions()
        let menus = Dictionary(uniqueKeysWithValues: Input.Kind.allCases.map { ($0, Menu($0.menu, definitions: d)) })
        XCTAssertEqual(menus[.agentStarted]?.tools.map(\.name), ["react"])
        XCTAssertEqual(menus[.agentFinished]?.tools.map(\.name), ["react"])
        XCTAssertEqual(menus[.said]?.tools.map(\.name), ["quiet", "react", "remember"])
        XCTAssertEqual(menus[.said]?.definition("remember")?.parameters[0].kind, .choice(["today"]))
        XCTAssertEqual(menus[.poked]?.tools.map(\.name), ["react"])
        XCTAssertEqual(menus[.newDay]?.tools.map(\.name), ["remember"])
        XCTAssertEqual(menus[.newDay]?.definition("remember")?.parameters[0].kind,
                       .choice(["about_you", "preference", "temperament", "moment"]))
        XCTAssertEqual(menus[.newDay]?.max["remember"], 4)
        // HARNESS.md §2's deadlines.
        XCTAssertEqual(Input.Kind.allCases.map(\.deadlineMs), [5000, 5000, 4000, 4000, 600_000])
    }

    func testSlotsOnlyForWhatNeedsWords() throws {
        let menu = Menu(Input.Kind.said.menu, definitions: try definitions())
        XCTAssertEqual(menu.slots([react("sulky", "silent")]), [])
        let slots = menu.slots([ToolCall("quiet", ["minutes": .number(15)]), react("happy"), remember("today")])
        XCTAssertEqual(slots.map(\.key), ["react.word", "remember.text"])
        XCTAssertEqual(slots.map(\.call), [1, 2])
        XCTAssertEqual(slots[0].kind, .word(Sounds.vocabulary))
        XCTAssertTrue(slots[0].optional)
        XCTAssertEqual(slots[1].kind, .text(maxLength: 80))
        XCTAssertFalse(slots[1].optional)
        XCTAssertEqual(slots[1].choice, "A note for later today: something the person said or asked to note.")
        XCTAssertEqual(slots[1].value("  demo on Thursday "), "demo on Thursday")
        XCTAssertNil(slots[1].value("none"))
        XCTAssertNil(slots[1].value(String(repeating: "x", count: 81)))
        XCTAssertNil(slots[0].value("kubernetes"))
    }

    func testCallsRunInTheMenusOrder() throws {
        let menu = Menu(Input.Kind.said.menu, definitions: try definitions())
        let quiet = ToolCall("quiet", ["minutes": .number(60)])
        XCTAssertEqual(menu.ordered([remember("today"), react("sulky", "silent"), quiet]),
                       [quiet, react("sulky", "silent"), remember("today")])
    }
}
