import Foundation
import XCTest
@testable import BrainKit

/// The brain kit (plan/kit/BRAIN-KIT.md) on its own, with toy outputs and
/// no Boop: events and the log, lines, rules, the prompt, the loop,
/// outputs and what takes a while, `Choice`, the tick and the socket in.
final class BrainKitTests: XCTestCase {
    nonisolated static let t0: Int64 = 1_790_690_400_000

    // MARK: Events and the log (§2)

    /// §2.1–2.2: one JSON line, `seq`, `at`, `source`, `kind`, `line` when
    /// there is one, then `data` with its keys sorted; the kit's own events
    /// are `self`'s, `for` what they answer.
    func testAnEventIsOneLine() throws {
        var e = Event(source: "ci", kind: "build_failed", data: ["run": 812, "branch": "main"])
        e.seq = 408
        e.at = 1_790_690_940_000
        XCTAssertEqual(e.jsonLine, #"{"seq":408,"at":1790690940000,"source":"ci","kind":"build_failed","data":{"branch":"main","run":812}}"#)
        XCTAssertEqual(Event(jsonLine: e.jsonLine), e, "it reads back")
        var lined = Event(source: "ci", kind: "deploy", line: "Deployed.")
        lined.seq = 1
        XCTAssertEqual(lined.jsonLine, #"{"seq":1,"at":0,"source":"ci","kind":"deploy","line":"Deployed.","data":{}}"#)
        let did = Event.did("Beacon flashed red on its own.", for: 408, action: "flash", by: "rule", facts: ["for": 1, "color": "red"])
        XCTAssertEqual(did.source, "self")
        XCTAssertEqual(did.kind, "did")
        XCTAssertEqual(did.about, 408, "the kit's own keys win a clash")
        XCTAssertEqual(did["color"], "red")
        XCTAssertTrue(did.isKit)
        XCTAssertEqual(Event.ended(412, action: "play", by: "brain", failed: "no device").data,
                       ["for": 412, "action": "play", "by": "brain", "outcome": "failed", "why": "no device"])
        try XCTAssertEqual(JSONValue(foundation: try JSONSerialization.jsonObject(with: Data("[0.81, 2, true]".utf8))) as JSONValue,
                       .array([.double(0.81), .int(2), .bool(true)]), "a fraction stays one")
    }

    /// §2.3: a file a day, the last day in memory, `seq` on across a
    /// relaunch, a torn line skipped and ended, another shape read by
    /// `decode`, and files past `keptDays` deleted.
    func testTheLogKeepsADayAndReadsItBack() throws {
        let dir = tempDir("kit-log")
        defer { try? FileManager.default.removeItem(at: dir) }
        var options = Log.Options()
        options.day = { ms in ms < Self.t0 ? "2026-09-29" : "2026-09-30" }
        options.decode = { line in line.hasPrefix("old ") ? Event(seq: 90, at: Self.t0 + 5, source: "old", kind: "x") : nil }
        let log = Log(folder: dir, options: options)
        let day = 24 * 3_600_000 as Int64
        log.append(Event(at: Self.t0 - day - 1, source: "ci", kind: "old_news"), now: Self.t0)
        log.append(Event(source: "ci", kind: "a"), now: Self.t0)
        log.append(Event(source: "ci", kind: "b"), now: Self.t0 + 1)
        let today = dir.appendingPathComponent("2026-09-30.jsonl")
        try (String(contentsOf: today, encoding: .utf8) + "old line\n" + #"{"seq":99,"at":"#).write(to: today, atomically: true, encoding: .utf8)
        try "{}\n".write(to: dir.appendingPathComponent("2026-09-01.jsonl"), atomically: true, encoding: .utf8)

        let again = Log(folder: dir, options: options)
        let read = again.load(now: Self.t0 + 10)
        XCTAssertEqual(read.map(\.kind), ["a", "b", "x"], "the last day, the older shape too, the torn line skipped")
        XCTAssertEqual(again.lastSeq, 90, "seq goes on from the files' last")
        XCTAssertEqual(again.append(Event(source: "ci", kind: "c"), now: Self.t0 + 11).seq, 91)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("2026-09-01.jsonl").path), "past 14 days")
        try XCTAssertTrue(try String(contentsOf: today, encoding: .utf8).hasSuffix("\n"), "the torn line was ended")
    }

    /// §2.4: a transform's view stops just before its event; the rest see
    /// everything so far.
    func testLookingBack() {
        let log = Log()
        for (i, kind) in ["failed", "press", "failed", "passed", "failed"].enumerated() {
            log.append(Event(source: "ci", kind: kind, data: ["n": .int(Int64(i))]), now: Self.t0 + Int64(i) * 1000)
        }
        let last = log.events.last!
        let before = log.view(before: last)
        XCTAssertEqual(before.now, last.at)
        XCTAssertEqual(before.last("failed")?["n"], 2, "not the event itself")
        XCTAssertEqual(before.count("failed"), 2)
        XCTAssertEqual(before.count("failed", since: before.last("passed")), 0)
        XCTAssertEqual(before.all("failed", where: { $0["n"]?.int == 2 }).map(\.seq), [3])
        XCTAssertEqual(before.count("failed", within: 2000), 1, "at or after now - 2 s")
        XCTAssertEqual(before.events(after: 3).map(\.kind), ["passed"])
        XCTAssertNil(before.event(last.seq))
        XCTAssertEqual(log.view(now: Self.t0 + 4000).count("failed"), 3)
    }

    // MARK: Lines and rules (§3–4)

    /// §3.1–3.2: a transform's line (nil hides the event), a registered
    /// kind with none shows the event's own line or its data, a kind never
    /// registered has no line, and a JSON file registers templates.
    func testLines() throws {
        let rig = KitRig()
        rig.h.input("build_failed", wake: 1) { e, log in
            let streak = log.count("build_failed", since: log.last("build_passed"))
            return streak == 0 ? "The build on \(e["branch"]!.string!) failed."
                : "The build on \(e["branch"]!.string!) failed again, \(streak + 1) in a row."
        }
        rig.h.input("quiet") { _, _ in nil }
        rig.h.input("hold")
        let file = tempDir("kit-events").appendingPathComponent("events.json")
        try Data(#"{"build_passed":{"line":"The build on {branch} passed for {who}.","wake":1}}"#.utf8).write(to: file)
        try rig.sync { try rig.h.load(file) }
        func line(_ e: Event) -> String? { rig.sync { rig.h.line(e.seq)?.text } }
        XCTAssertEqual(line(rig.emit("build_failed", ["branch": "main"])), "The build on main failed.")
        XCTAssertEqual(line(rig.emit("build_failed", ["branch": "main"])), "The build on main failed again, 2 in a row.")
        XCTAssertEqual(line(rig.emit("build_passed", ["branch": "main"])), "The build on main passed for {who}.",
                       "a field the event hasn't is left as written")
        XCTAssertEqual(line(rig.emit("build_failed", ["branch": "main"])), "The build on main failed.")
        XCTAssertNil(line(rig.emit("quiet")), "hidden")
        XCTAssertEqual(line(rig.emit("hold", ["secs": 2])), "hold: secs 2")
        XCTAssertEqual(line(rig.sync { rig.h.emit(Event(source: "ci", kind: "hold", line: "Held for 2 s.")) }), "Held for 2 s.")
        XCTAssertNil(line(rig.emit("unregistered", ["x": 1])), "logged, with no line")
    }

    /// §4: a rule runs at once, before the brain hears of the event, and
    /// what it did goes under it: NOW shows it, or that nothing was done.
    func testRulesRunAtOnceAndNowShowsWhatTheyDid() {
        let rig = KitRig()
        rig.h.input("build_failed", wake: 1) { e, _ in "The build on \(e["branch"]!.string!) failed." }
        rig.h.input("press", wake: 0) { _, _ in "You pressed the button." }
        var seen: [String] = []
        rig.h.on("*") { e in seen.append(e.kind) }
        rig.h.on("build_failed") { e in rig.h.did("Beacon flashed red on its own.", for: e, action: "flash") }
        let failed = rig.emit("build_failed", ["branch": "main"])
        XCTAssertEqual(seen, ["build_failed", "did"], "in the order they were registered, for every event, the kit's own too")
        XCTAssertEqual(rig.sync { rig.h.prompt(for: failed) }.components(separatedBy: "\n\n").last,
                       "NOW (14:09, Wednesday)\nThe build on main failed.\nBeacon flashed red on its own.")
        let press = rig.emit("press")
        XCTAssertTrue(rig.sync { rig.h.prompt(for: press) }.hasSuffix("You pressed the button.\nBeacon did nothing on its own."))
    }

    // MARK: The prompt (§7)

    /// §7.2: your sections (an empty one left out), how to read the rest,
    /// HISTORY with relative times, notes and what was done in order, a
    /// failed or failed-ended one left out and an open one in progress,
    /// the closing line, then NOW. The same log gives the same text.
    func testThePromptsLayout() {
        let rig = KitRig()
        rig.h.input("build_failed", wake: 1) { e, _ in Line("The build on \(e["branch"]!.string!) failed.", notes: ["Run \(e["run"]!.int!)."]) }
        rig.h.input("press", wake: 0) { _, _ in "You pressed the button." }
        rig.h.section { _ in "GUIDE\nBe a light." }
        rig.h.section { _ in "" }
        rig.h.section { _ in nil }
        rig.h.section { log in "TONE\n\(log.count("press"))" }
        rig.h.closing { _, _ in "Beacon has been worried for 8 min." }
        let first = rig.emit("build_failed", ["branch": "main", "run": 812])
        rig.sync {
            rig.h.did("Beacon flashed red on its own.", for: first, action: "flash")
            rig.h.emit(Event.did("Beacon felt worried.", for: first.seq, action: "tone", by: "brain"))
            rig.h.emit(Event.did("no device", for: first.seq, action: "play", by: "brain", ok: false))
            let open = rig.h.emit(Event.did("Beacon wobbled.", for: first.seq, action: "play", by: "brain", open: true))
            let gone = rig.h.emit(Event.did("Beacon cheered.", for: first.seq, action: "play", by: "brain", open: true))
            rig.h.emit(Event.ended(gone.seq, action: "play", by: "brain", failed: "skipped"))
            _ = open
        }
        rig.clock.now += 4 * 60_000
        let press = rig.emit("press")
        let prompt = rig.sync { rig.h.prompt(for: press) }
        XCTAssertEqual(prompt, """
            GUIDE
            Be a light.

            TONE
            1

            How to read HISTORY and NOW:
            - HISTORY is oldest first. Each line says how long ago it happened.
              Lines indented under it add to it: its notes, then what Beacon did.
              A line of what Beacon did ending in (in progress) hasn't finished yet.
            - NOW is what to react to. Its last line is what Beacon already did on
              its own, by reflex.

            HISTORY (oldest first; indented lines add to the line above)
            4 min ago: The build on main failed.
              Run 812.
              Beacon flashed red on its own.
              Beacon felt worried.
              Beacon wobbled. (in progress)
            Beacon has been worried for 8 min.

            NOW (14:09, Wednesday)
            You pressed the button.
            Beacon did nothing on its own.
            """)
        XCTAssertEqual(rig.sync { rig.h.prompt(for: press) }, prompt, "a pure function of the log and the time")
        XCTAssertEqual(Harness.ago(59_999), "just now")
        XCTAssertEqual(Harness.ago(60_000), "1 min ago")
        XCTAssertEqual(Harness.ago(3_599_999), "59 min ago")
        XCTAssertEqual(Harness.ago(7_200_000), "2 h ago")
    }

    /// §7.2: HISTORY holds the last 10 minutes, or back to `reachBack`
    /// when that's further; then at most the newest 40, and any older one
    /// in that time whose `did` is still in progress. How to read it can be
    /// yours, or none.
    func testHistoryReachesBackAndHoldsForty() {
        var options = Harness.Options()
        options.reading = .none
        let rig = KitRig(options: options)
        rig.h.input("tick", wake: 0) { e, _ in "Tick \(e["n"]!.int!)." }
        var back: Int64?
        rig.h.reachBack { _, _ in back }
        let old = rig.emit("tick", ["n": 0])
        rig.sync { _ = rig.h.emit(Event.did("Beacon hummed.", for: old.seq, action: "hum", by: "brain", open: true)) }
        rig.clock.now += 60_000
        for n in 1...41 { rig.emit("tick", ["n": .int(Int64(n))]) }
        var now = rig.emit("tick", ["n": 42])
        func history() -> [String] {
            let prompt = rig.sync { rig.h.prompt(for: now) }
            let lines = prompt.components(separatedBy: "\n\n")[0].split(separator: "\n").map(String.init)
            return lines.filter { $0.contains("Tick") }
        }
        XCTAssertEqual(history().count, 1 + 40, "the newest 40, and the one still in progress")
        XCTAssertEqual(history().first, "1 min ago: Tick 0.")
        XCTAssertEqual(history()[1], "just now: Tick 2.")
        rig.clock.now += 11 * 60_000
        now = rig.emit("tick", ["n": 43])
        XCTAssertEqual(history(), [], "all past 10 minutes, in progress or not")
        back = BrainKitTests.t0
        XCTAssertEqual(history().first, "12 min ago: Tick 0.", "reaching back")
        XCTAssertEqual(history().count, 1 + 40)
        XCTAssertFalse(rig.sync { rig.h.prompt(for: now) }.contains("How to read"), "none of the kit's words")
    }

    // MARK: The loop (§9)

    /// §9: one call at a time; what goes next is worked out from the log:
    /// the highest wake first, oldest first within it, one at 0 passed
    /// over for anything newer, none older than 10 s, and a held one
    /// logged as a pass with why, the brain not asked.
    func testWhatTheBrainAnswersNext() {
        let gate = DispatchSemaphore(value: 0)
        let asked = Lines()
        let brain = ScriptedBrain { state, _ in
            asked.add(String(state.split(separator: "\n").reversed()[1]))
            gate.wait()
            return [:]
        }
        let rig = KitRig(brain: brain)
        for (kind, wake) in [("routine", 0), ("finish", 1), ("talk", 2)] {
            rig.h.input(kind, wake: wake) { e, _ in "\(kind) \(e["n"]!.int!)" }
        }
        var holding = false
        rig.h.input("press", wake: 0) { _, _ in "press" }
        rig.h.hold("press") { _, _ in holding ? "Beacon is busy" : nil }
        rig.emit("routine", ["n": 1])
        eventually("the first call") { asked.all == ["routine 1"] }
        rig.emit("routine", ["n": 2])
        rig.emit("finish", ["n": 3])
        rig.emit("routine", ["n": 4])
        rig.emit("finish", ["n": 5])
        rig.emit("talk", ["n": 6])
        rig.emit("routine", ["n": 7])
        for _ in 0..<5 { gate.signal() }
        eventually("the rest") { rig.sync { rig.h.idle } }
        XCTAssertEqual(asked.all, ["routine 1", "talk 6", "finish 3", "finish 5", "routine 7"],
                       "what you said first, finishes oldest first, and the newest routine one: \(asked.all)")

        holding = true
        rig.emit("press")
        let held = rig.sync { rig.h.log.events.last { $0.kind == Event.pass } }
        XCTAssertEqual(held?["held"], "Beacon is busy")
        XCTAssertEqual(asked.all.count, 5, "the brain wasn't asked")
        holding = false
        rig.clock.now += 11_000
        XCTAssertTrue(rig.sync { rig.h.idle }, "nothing older than 10 s waits, the held press answered")
    }

    /// §5.1, §9: each output gets only its own answers, in order; nil does
    /// nothing; each result is a `did` for the event, by the brain. A brain
    /// that fails, or answers late, drops the call and runs no output. The
    /// `pass` event keeps the answers.
    func testOutputsAndDroppedCalls() throws {
        let rig = KitRig(brain: ScriptedBrain { _, _ in
            ["a1": Answer(choice: "x", probabilities: ["x": 0.8123, "y": 0.1877]), "b1": Answer(choice: "y")]
        })
        let a = KitOutput("a", keys: ["a1"], result: .done("Beacon did a."))
        let b = KitOutput("b", keys: ["b1"], result: nil)
        rig.h.output(a)
        rig.h.output(b)
        rig.h.input("go", wake: 0) { _, _ in "Go." }
        var passes: [Harness.Pass] = []
        rig.h.onPass = { passes.append($0) }
        let go = rig.emit("go")
        eventually("the pass") { rig.sync { !passes.isEmpty } }
        XCTAssertEqual(a.got.map { Array($0.keys) }, [["a1"]])
        XCTAssertEqual(b.got.map { Array($0.keys) }, [["b1"]])
        let dids = rig.sync { rig.h.log.dids(for: go.seq) }
        XCTAssertEqual(dids.map(\.action), ["a"], "nil logs nothing")
        XCTAssertEqual(dids.first?["by"], "brain")
        let pass = try XCTUnwrap(rig.sync { rig.h.log.events.last { $0.kind == Event.pass } })
        XCTAssertEqual(pass.about, go.seq)
        XCTAssertEqual(pass["answers"]?.object?["a1"]?.object?["p"]?.object?["x"], .double(0.812), "three places")
        XCTAssertEqual(passes.first?.actions.map(\.name), ["a"])
        XCTAssertEqual(passes.first?.prompt?.hasSuffix("NOW (14:09, Wednesday)\nGo.\nBeacon did nothing on its own."), true)

        let failing = KitRig(brain: ScriptedBrain { _, _ in throw BrainError("nope") })
        let c = KitOutput("c", keys: ["c1"], result: .done("Beacon did c."))
        failing.h.output(c)
        failing.h.input("go", wake: 0) { _, _ in "Go." }
        failing.emit("go")
        eventually("dropped") { failing.sync { failing.h.log.events.contains { $0.kind == Event.pass } } }
        XCTAssertEqual(failing.sync { failing.h.log.events.last { $0.kind == Event.pass }?["dropped"] }, "nope")
        XCTAssertTrue(c.got.isEmpty)

        var late = Harness.Options()
        late.deadlineMs = 50
        let notes = Lines()
        let slow = KitRig(brain: SlowKitBrain(ms: 200), options: late, note: { notes.add($0) })
        slow.h.input("go", wake: 0) { _, _ in "Go." }
        slow.emit("go")
        eventually("late") { slow.sync { slow.h.log.events.contains { $0.kind == Event.pass } } }
        XCTAssertEqual(slow.sync { slow.h.log.events.last { $0.kind == Event.pass }?["dropped"] }, "late: no answer within 50 ms")
        eventually("its answer, timed") { notes.all.contains { $0.hasPrefix("harness: slow answered after ") } }
    }

    /// §9: the deadline cuts a call off on time: its timer fires within
    /// 5 ms of it, where the system's default leeway let it fire up to 7%
    /// late, so an answer just past it was kept or dropped by chance.
    func testTheDeadlineComesOnTime() async {
        XCTAssertEqual(Harness.Options().deadlineMs, 1500)
        var options = Harness.Options()
        options.loop = false
        let runs = (0..<4).map { _ -> (KitRig, Event) in
            let rig = KitRig(brain: SlowKitBrain(ms: 3000), options: options)
            rig.h.input("go", wake: 0) { _, _ in "Go." }
            return (rig, rig.emit("go"))
        }
        let ms = await withTaskGroup(of: Int.self) { group in
            for (rig, e) in runs {
                group.addTask {
                    let started = ContinuousClock.now
                    _ = await rig.h.respond(to: e)
                    return (ContinuousClock.now - started).ms
                }
            }
            var all: [Int] = []
            for await one in group { all.append(one) }
            return all
        }
        XCTAssertLessThan(ms.max() ?? 0, 1540, "\(ms)")
    }

    // MARK: What takes a while (§5.3)

    /// §5.3: a started result is an open `did`, in progress until its
    /// handle ends it; a handle ended before the kit had the result is
    /// kept; only the first end counts; one left open past `openFor` is
    /// ended on the tick; one open at a relaunch is ended as restarted.
    func testSomethingThatTakesAWhile() throws {
        let dir = tempDir("kit-open")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rig = KitRig(brain: ScriptedBrain(always: [:]), log: Log(folder: dir))
        let play = KitOutput("play", keys: ["play"], result: nil)
        rig.h.output(play, openFor: 20_000)
        rig.h.input("go", wake: 0) { _, _ in "Go." }
        func open() -> [Int] { rig.sync { rig.h.log.openDids.sorted() } }
        func ended(_ seq: Int) -> String? { rig.sync { rig.h.log.ended(seq)?["outcome"]?.string } }

        var handle = Pending()
        play.result = .started("Beacon wobbled.", handle)
        let first = rig.emit("go")
        eventually("started") { !open().isEmpty }
        let wobble = open()[0]
        XCTAssertTrue(rig.sync { rig.h.prompt(for: first) }.contains("Beacon did nothing on its own."))
        let later = rig.emit("tick")
        XCTAssertTrue(rig.sync { rig.h.prompt(for: later) }.contains("  Beacon wobbled. (in progress)"))
        rig.sync { handle.finish(.done) }
        XCTAssertEqual(ended(wobble), "done")
        rig.sync { handle.finish(.failed("too late")) }
        XCTAssertEqual(rig.sync { rig.h.log.events.filter { $0.kind == Event.ended }.count }, 1, "only the first end counts")

        handle = Pending()
        handle.finish(.failed("no device"))
        play.result = .started("Beacon cheered.", handle)
        rig.emit("go")
        eventually("its end, kept") { rig.sync { rig.h.log.events.filter { $0.kind == Event.ended }.count } == 2 }
        XCTAssertTrue(open().isEmpty)

        play.result = .started("Beacon wobbled.", Pending())
        rig.emit("go")
        eventually("started") { open().count == 1 }
        let stuck = open()[0]
        rig.clock.now += 19_999
        rig.sync { rig.h.tick() }
        XCTAssertNil(ended(stuck))
        rig.clock.now += 1
        rig.sync { rig.h.tick() }
        XCTAssertEqual(rig.sync { rig.h.log.ended(stuck)?["why"] }, .string(Harness.noWord))

        play.result = .started("Beacon wobbled.", Pending())
        rig.emit("go")
        eventually("started") { open().count == 1 }
        let relaunched = KitRig(log: Log(folder: dir))
        relaunched.clock.now = rig.clock.now
        let read = relaunched.sync { relaunched.h.resume() }
        XCTAssertGreaterThan(read.count, 0)
        XCTAssertEqual(relaunched.sync { relaunched.h.log.events.last?["why"] }, .string(Harness.restarted))
        XCTAssertTrue(relaunched.sync { relaunched.h.log.openDids.isEmpty })
    }

    // MARK: Forced passes (§5.4)

    /// §5.4: forced answers at probability 1, for no event, by who forced
    /// them, a choice that isn't offered left out; the `did` shows under
    /// the latest line before it. An output that acted outside a call
    /// while one ran sits that call's answers out.
    func testForcedPasses() {
        let gate = DispatchSemaphore(value: 0)
        let rig = KitRig(brain: ScriptedBrain { _, _ in
            gate.wait()
            return ["a1": Answer(choice: "x")]
        })
        let a = KitOutput("a", keys: ["a1"], result: .done("Beacon did a."))
        rig.h.output(a)
        rig.h.input("go", wake: 0) { _, _ in "Go." }
        let go = rig.emit("go")
        let ran = rig.sync { rig.h.force(["a1": "y", "zz": "q"], by: "dashboard") }
        XCTAssertEqual(ran.map(\.name), ["a"])
        XCTAssertEqual(a.got.last?["a1"], Answer(choice: "y", probabilities: ["y": 1]))
        let forced = rig.sync { rig.h.log.events.last { $0.kind == Event.pass } }
        XCTAssertEqual(forced?["by"], "dashboard")
        XCTAssertEqual(forced?["for"], .null)
        gate.signal()
        eventually("the call") { rig.sync { rig.h.log.answered(go.seq) } }
        XCTAssertEqual(a.got.count, 1, "it acted while the call ran, so it sat that call's answers out")
        let next = rig.emit("tick")
        XCTAssertTrue(rig.sync { rig.h.prompt(for: next) }.contains("Go.\n  Beacon did a."), "under the latest line before it")
    }

    // MARK: Choice (§6)

    /// §6: its value is the latest change in the log, or its start;
    /// staying is nothing; a pick it didn't offer changes nothing; `set`
    /// changes it whatever the options; a relaunch reads it back.
    func testChoice() {
        let log = Log()
        let tone = Choice(name: "tone", start: "calm", question: "After NOW, how does Beacon feel?",
                          judgeBy: "the TONE section, its reason to leave",
                          said: { from, to in "Beacon went from \(from) to \(to)." },
                          options: { current, _, _ in
                              current == "calm" ? [Option("calm", "Stay calm."), Option("worried", "Failures keep coming.")]
                                  : [Option("worried", "Stay worried."), Option("calm", "A build passed.")]
                          })
        func view() -> LogView { log.view(now: Self.t0) }
        func run(_ pick: String) -> ActionResult? {
            let result = tone.run(["tone": Answer(choice: pick)], now: nil, log: view())
            if let result { log.append(Event.did(result.message, for: nil, action: "tone", by: "brain", facts: result.facts), now: Self.t0) }
            return result
        }
        XCTAssertEqual(tone.value(view()), "calm")
        XCTAssertNil(tone.since(view()))
        XCTAssertEqual(tone.questions(now: nil, log: view())[0].options.map(\.name), ["calm", "worried"])
        XCTAssertEqual(tone.questions(now: nil, log: view())[0].about, "the NOW and HISTORY sections")
        XCTAssertNil(run("calm"), "staying is nothing")
        XCTAssertNil(run("grim"), "not offered")
        XCTAssertEqual(run("worried"), .done("Beacon went from calm to worried.", facts: ["from": "calm", "to": "worried"]))
        XCTAssertEqual(tone.value(view()), "worried")
        XCTAssertEqual(tone.since(view()), Self.t0)
        XCTAssertEqual(tone.questions(now: nil, log: view())[0].options.map(\.name), ["worried", "calm"])
        XCTAssertEqual(tone.set("grim", log: view())?.message, "Beacon went from worried to grim.", "whatever the options")
        let again = Choice(name: "tone", start: "calm", question: "?", judgeBy: "?", options: { _, _, _ in [] })
        XCTAssertEqual(again.value(view()), "worried", "nothing to restore: it's the log's")
    }

    // MARK: The tick (§10)

    /// §10: a timed check emits what it returns, and doesn't fire twice
    /// because the log says it already did.
    func testTimedChecks() {
        let rig = KitRig()
        rig.h.input("build_failed", wake: 1) { _, _ in "The build failed." }
        rig.h.input("still_red", wake: 1) { _, _ in "The build has been red for an hour." }
        rig.h.tick { now, log in
            guard let red = log.last("build_failed"), now - red.at >= 3_600_000, log.count("still_red", since: red) == 0 else { return nil }
            return Event(source: "beacon", kind: "still_red")
        }
        rig.emit("build_failed")
        rig.clock.now += 3_599_999
        rig.sync { rig.h.tick() }
        XCTAssertEqual(rig.sync { rig.h.log.view(now: rig.clock.now).count("still_red") }, 0)
        rig.clock.now += 1
        rig.sync { rig.h.tick() }
        rig.sync { rig.h.tick() }
        XCTAssertEqual(rig.sync { rig.h.log.view(now: rig.clock.now).count("still_red") }, 1, "once")
    }

    /// §3.3: another process sends events through the socket, which the
    /// kit emits like any other.
    func testTheSocketIn() throws {
        let rig = KitRig()
        rig.h.input("build_failed", wake: 1) { e, _ in "The build on \(e["branch"]!.string!) failed." }
        let path = NSTemporaryDirectory() + "kit-\(UUID().uuidString.prefix(6)).sock"
        let server = EventServer(path: path) { e in rig.home.async { rig.h.emit(e) } }
        try server.start()
        defer { server.stop() }
        try EventServer.send(Event(source: "ci", kind: "build_failed", data: ["branch": "main", "run": 812]), to: path)
        eventually("emitted") { rig.sync { rig.h.log.view(now: rig.clock.now).count("build_failed") } == 1 }
        let e = try XCTUnwrap(rig.sync { rig.h.log.events.last })
        XCTAssertEqual(e.source, "ci")
        XCTAssertEqual(e["run"], 812)
        XCTAssertEqual(rig.sync { rig.h.line(e.seq)?.text }, "The build on main failed.")
        XCTAssertNil(EventServer.decode(Data(#"{"kind":"x"}"#.utf8)), "a source is needed")
    }

    /// §9, the evals: one event straight through, without the loop: nil
    /// when it doesn't wake the brain or is held.
    func testOneEventStraightThrough() async {
        var options = Harness.Options()
        options.loop = false
        let rig = KitRig(brain: ScriptedBrain(always: [:]), options: options)
        rig.h.input("go", wake: 0) { _, _ in "Go." }
        rig.h.input("held", wake: 0) { _, _ in "Held." }
        rig.h.hold("held") { _, _ in "no" }
        rig.h.input("quiet") { _, _ in "Quiet." }
        let go = rig.emit("go")
        XCTAssertFalse(rig.sync { rig.h.log.answered(go.seq) }, "no loop")
        let pass = await rig.h.respond(to: go)
        XCTAssertEqual(pass?.line, "Go.")
        let held = await rig.h.respond(to: rig.emit("held"))
        XCTAssertNil(held)
        let quiet = await rig.h.respond(to: rig.emit("quiet"))
        XCTAssertNil(quiet)
    }
}

/// A clock the kit tests move by hand.
final class KitClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: Int64
    init(_ ms: Int64) { self.ms = ms }
    var now: Int64 {
        get { lock.withLock { ms } }
        set { lock.withLock { ms = newValue } }
    }
}

/// A harness named Beacon on its own queue and a hand-moved clock, its
/// heading fixed.
final class KitRig: @unchecked Sendable {
    let home = DispatchQueue(label: "kit.test")
    let clock = KitClock(BrainKitTests.t0)
    let h: Harness

    init(brain: (any Brain)? = nil, options: Harness.Options = Harness.Options(), log: Log = Log(),
         note: @escaping (String) -> Void = { _ in }) {
        var o = options
        o.heading = { _ in "14:09, Wednesday" }
        let clock = self.clock
        h = Harness(name: "Beacon", brain: brain, log: log, clock: .init(now: { clock.now }), queue: home, options: o, note: note)
    }

    func sync<T>(_ body: () throws -> T) rethrows -> T { try home.sync(execute: body) }

    @discardableResult
    func emit(_ kind: String, _ data: [String: JSONValue] = [:]) -> Event {
        sync { h.emit(source: "ci", kind: kind, data: data) }
    }
}

/// An output with fixed keys that records the answers it gets and returns
/// `result`. Not nested in a test: the runner's generator would take it for
/// one.
final class KitOutput: Action, @unchecked Sendable {
    let name: String
    let keys: [String]
    var got: [Answers] = []
    var result: ActionResult?
    init(_ name: String, keys: [String], result: ActionResult?) {
        self.name = name
        self.keys = keys
        self.result = result
    }
    func questions(now: Event?, log: LogView) -> [Question] {
        keys.map { Question(key: $0, text: "?", about: "the NOW section", judgeBy: "x", options: [Option("x", "X"), Option("y", "Y")]) }
    }
    func run(_ answers: Answers, now: Event?, log: LogView) -> ActionResult? {
        got.append(answers)
        return result
    }
}

struct SlowKitBrain: Brain {
    let id = "slow"
    let ms: Int
    func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        try await Task.sleep(for: .milliseconds(ms))
        return [:]
    }
}
