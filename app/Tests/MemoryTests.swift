import Foundation
import XCTest
@testable import BoopKit

/// A memory store in a fresh temporary directory.
final class MemoryRig {
    let dir: URL
    var logs: [String] = []
    var store: MemoryStore!

    init(setUp: Bool = true, day: String = "2026-10-14") throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-memory-\(UUID().uuidString)")
        try reopen()
        if setUp {
            try store.setUp(name: "Pip", nature: .cheeky, seed: 0x7f3a, today: "2026-10-02")
            store.apply(.newDay(date: day, firstSeen: "08:52"))
        }
    }

    func reopen() throws {
        store = try MemoryStore(directory: dir, steering: "# Boop\n", log: { [weak self] in self?.logs.append($0) })
    }

    func file(_ name: String) -> String { (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? "" }

    /// Writes a file as a person editing it by hand would, with a later
    /// modification time so the store notices.
    func edit(_ name: String, _ text: String) throws {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }
}

final class MemoryTests: XCTestCase {
    static let sample = """
        ## Boop
        name: Pip · hatched: 2026-10-02 · nature: cheeky · seed: 7f3a

        ### Temperament
        Nosy and a bit smug. Trusts Codex more than it used to.
        Gets huffy about flaky tests.

        ### Moments
        - 2026-10-09: first all-nighter together; the migration finally passed.

        ## About you
        - Ships on Fridays.
        - Mostly works on landing and jetpack.

        ## Preferences
        - Likes it quiet before 10am.

        """

    func testLongTermRoundTrips() throws {
        let lt = try LongTerm.parse(MemoryTests.sample)
        XCTAssertEqual(lt.name, "Pip")
        XCTAssertEqual(lt.nature, .cheeky)
        XCTAssertEqual(lt.seed, 0x7f3a)
        XCTAssertEqual(lt.temperament.count, 2)
        XCTAssertEqual(lt.moments, [.init(date: "2026-10-09", text: "first all-nighter together; the migration finally passed.")])
        XCTAssertEqual(lt.aboutYou, ["Ships on Fridays.", "Mostly works on landing and jetpack."])
        XCTAssertEqual(lt.preferences, ["Likes it quiet before 10am."])
        XCTAssertEqual(lt.markdown, MemoryTests.sample)
        try XCTAssertEqual(try LongTerm.parse(lt.markdown), lt)
    }

    /// Files written before the cut (2026-09-26) have a Growth section in
    /// `long-term.md` and a mood on the Today line. They still load; the next
    /// write leaves those out.
    func testFilesFromBeforeTheCutStillLoad() throws {
        let oldLongTerm = MemoryTests.sample.replacingOccurrences(
            of: "## About you\n",
            with: "### Growth\nxp: 1240 · level: 25 · last fed: 2026-10-14 · lost: 3\n\n## About you\n")
        let lt = try LongTerm.parse(oldLongTerm)
        try XCTAssertEqual(lt, try LongTerm.parse(MemoryTests.sample))
        XCTAssertEqual(lt.moments.count, 1, "the Growth heading ends Moments")
        XCTAssertEqual(lt.markdown, MemoryTests.sample)

        let oldShortTerm = "## Today\n2026-10-14 · first seen 08:52 · mood: a bit frazzled\n\n## Notes\n- a note\n\n## Happened\n"
        let st = try ShortTerm.parse(oldShortTerm)
        XCTAssertEqual(st.date, "2026-10-14")
        XCTAssertEqual(st.firstSeen, "08:52")
        XCTAssertEqual(st.notes, ["a note"])
        XCTAssertEqual(st.markdown, "## Today\n2026-10-14 · first seen 08:52\n\n## Notes\n- a note\n\n## Happened\n")

        // Through the store: both load, and the next change rewrites them.
        let rig = try MemoryRig()
        try rig.edit("long-term.md", oldLongTerm)
        try rig.edit("short-term.md", oldShortTerm)
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-14")
        XCTAssertFalse(rig.logs.contains { $0.contains("didn't read") }, "\(rig.logs)")
        XCTAssertNotNil(try? rig.store.remember("Likes tests before lunch.", as: .preference).get())
        _ = rig.store.note("landing launches Monday")
        XCTAssertFalse(rig.file("long-term.md").contains("Growth"))
        XCTAssertFalse(rig.file("short-term.md").contains("mood"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.dir.appendingPathComponent("long-term.md.broken").path))
    }

    func testShortTermRoundTrips() throws {
        let text = """
            ## Today
            2026-10-14 · first seen 08:52

            ## Notes
            - landing: flaky tests, third attempt
            - said "shut up for an hour" at 13:10

            ## Happened
            - 14:02 codex · landing · tests · failed
            - 14:05 claude · jetpack · finished (18 min)

            """
        let st = try ShortTerm.parse(text)
        XCTAssertEqual(st.date, "2026-10-14")
        XCTAssertEqual(st.firstSeen, "08:52")
        XCTAssertEqual(st.notes.count, 2)
        XCTAssertEqual(st.happened.last, "14:05 claude · jetpack · finished (18 min)")
        XCTAssertEqual(st.markdown, text)
    }

    func testUnreadableFilesThrow() throws {
        try XCTAssertThrowsError(try LongTerm.parse("hello"))
        try XCTAssertThrowsError(try LongTerm.parse(MemoryTests.sample.replacingOccurrences(of: "seed: 7f3a", with: "seed: lots")))
        try XCTAssertThrowsError(try LongTerm.parse(MemoryTests.sample.replacingOccurrences(of: "nature: cheeky", with: "nature: grumpy")))
        try XCTAssertThrowsError(try LongTerm.parse(MemoryTests.sample.replacingOccurrences(of: "2026-10-09:", with: "last week:")))
        try XCTAssertThrowsError(try ShortTerm.parse("## Today\nyesterday\n"))
        try XCTAssertThrowsError(try ShortTerm.parse("## Today\n2026-02-30 · first seen 08:00\n"))
    }

    func testSetUpWritesLongTermAndASnapshot() throws {
        let rig = try MemoryRig()
        XCTAssertTrue(rig.file("long-term.md").hasPrefix("## Boop\nname: Pip · hatched: 2026-10-02 · nature: cheeky · seed: 7f3a\n"))
        XCTAssertTrue(rig.file("history/2026-10-02/long-term.md").contains("name: Pip"))
        try XCTAssertThrowsError(try rig.store.setUp(name: "Bo", nature: .sweet, seed: 1, today: "2026-10-14"))
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-14")
        XCTAssertEqual(Dialect(seed: rig.store.longTerm!.seed), Dialect(seed: 0x7f3a))
        // The brains get Boop's name with the memory (HARNESS.md §6).
        XCTAssertEqual(rig.store.promptMemory().boopName, "Pip")
    }

    func testNamesThatBreakTheBoopLineAreRefused() throws {
        let rig = try MemoryRig(setUp: false)
        try XCTAssertThrowsError(try rig.store.setUp(name: "Pip · xp: 9", nature: .sweet, seed: 1, today: "2026-10-14"))
        try XCTAssertThrowsError(try rig.store.setUp(name: "", nature: .sweet, seed: 1, today: "2026-10-14"))
        XCTAssertFalse(rig.store.isSetUp)
    }

    func testCoreEffectsLandInTheFiles() throws {
        let rig = try MemoryRig()
        rig.store.apply(.happened("14:02 codex · landing · tests · failed"))
        let longTerm = rig.file("long-term.md")
        rig.store.apply(.state(StateSnapshot.sample))  // ignored
        rig.store.apply(.moment(anim: "cheer"))  // ignored
        XCTAssertTrue(rig.file("short-term.md").hasPrefix("## Today\n2026-10-14 · first seen 08:52\n"))
        XCTAssertTrue(rig.file("short-term.md").contains("- 14:02 codex · landing · tests · failed\n"))
        XCTAssertEqual(rig.file("long-term.md"), longTerm)
    }

    func testHappenedKeepsTheLastForty() throws {
        let rig = try MemoryRig()
        for i in 0..<60 { rig.store.apply(.happened("14:\(i) claude · p · finished (1 min)")) }
        let st = try XCTUnwrap(rig.store.shortTerm)
        XCTAssertEqual(st.happened.count, 40)
        XCTAssertEqual(st.happened.first, "14:20 claude · p · finished (1 min)")
    }

    func testNotesKeepTheNewestTenOfEightyCharacters() throws {
        let rig = try MemoryRig()
        for i in 0..<12 { XCTAssertNotNil(try? rig.store.note("note number \(i)").get()) }
        XCTAssertEqual(rig.store.shortTerm!.notes.count, 10)
        XCTAssertEqual(rig.store.shortTerm!.notes.first, "note number 2")
        XCTAssertEqual(rig.store.note(String(repeating: "a", count: 81)), .failure(Refusal("longer than 80 characters")))
        XCTAssertEqual(rig.store.note("note number 11"), .failure(Refusal("already noted")))
    }

    func testShortTermStaysWithinItsBudget() throws {
        let rig = try MemoryRig()
        for i in 0..<10 { _ = rig.store.note(String(repeating: "word ", count: 15) + "\(i)") }
        for i in 0..<40 {
            rig.store.apply(.happened("14:\(i) claude · a-rather-long-project-name · docs · finished (125 min)"))
        }
        XCTAssertLessThanOrEqual(rig.store.shortTermText.utf8.count, MemoryLimits.shortTermBytes)
        XCTAssertEqual(rig.store.shortTerm!.notes.count, 10)
        XCTAssertGreaterThan(rig.store.shortTerm!.happened.count, 10)
    }

    func testRememberRespectsSectionLimits() throws {
        let rig = try MemoryRig()
        for i in 0..<30 { XCTAssertNotNil(try? rig.store.remember("fact \(i)", as: .aboutYou).get(), "\(i)") }
        XCTAssertEqual(rig.store.remember("fact 30", as: .aboutYou), .failure(Refusal("About you is full")))
        for i in 0..<15 { XCTAssertNotNil(try? rig.store.remember("likes \(i)", as: .preference).get(), "\(i)") }
        XCTAssertEqual(rig.store.remember("likes 15", as: .preference), .failure(Refusal("Preferences is full")))
        XCTAssertEqual(rig.store.remember("Fact 3.", as: .preference), .failure(Refusal("already remembered")))
        XCTAssertEqual(rig.store.remember(String(repeating: "b", count: 101), as: .aboutYou),
                       .failure(Refusal("longer than 100 characters")))
    }

    func testLongTermStaysWithinItsBudget() throws {
        let rig = try MemoryRig()
        var refused: Refusal?
        for i in 0..<45 {
            let kind: MemoryStore.FactKind = i < 30 ? .aboutYou : .preference
            if case .failure(let why) = rig.store.remember(String(repeating: "w", count: 95) + " \(i)", as: kind) {
                refused = why
                break
            }
        }
        XCTAssertEqual(refused, Refusal("long-term memory is full"))
        XCTAssertLessThanOrEqual(rig.file("long-term.md").utf8.count, MemoryLimits.longTermBytes)
    }

    func testPrivateThingsAreRefused() throws {
        let rig = try MemoryRig()
        let refused = [
            "works in ~/src/secret-project", "edits /Users/me/notes.txt", "fixed src/app/main.swift",
            "runs `rm -rf`", "let x = 3", "key sk-ant-api03-abcdefghijkl", "token ab12cd34ef56gh78ij90kl",
            "email me at a@b.com", "see https://example.com", "pairs with Alice on Fridays",
        ]
        for text in refused {
            if case .success = rig.store.remember(text, as: .aboutYou) { XCTFail("kept: \(text)") }
        }
        for text in ["Ships on Fridays.", "Mostly works on landing and jetpack.", "Likes CI green before lunch.",
                     "Reviews PRs before lunch.",
                     "Calls Boop Pip's friend."] {
            XCTAssertNotNil(try? rig.store.remember(text, as: .aboutYou).get(), text)
        }
        // Names are fine in today's notes; code and paths aren't.
        XCTAssertNotNil(try? rig.store.note("Alice reviewed landing").get())
        if case .success = rig.store.note("edited ~/x/y.swift") { XCTFail("kept a path in notes") }
    }

    func testForgetRemovesOneMatch() throws {
        let rig = try MemoryRig()
        _ = rig.store.remember("Ships on Fridays.", as: .aboutYou)
        _ = rig.store.remember("Likes it quiet before 10am.", as: .preference)
        _ = rig.store.remember("Likes jazz.", as: .preference)
        XCTAssertEqual(rig.store.forget("likes"), .failure(Refusal("2 lines match")))
        XCTAssertEqual(rig.store.forget("tabs"), .failure(Refusal("nothing matches")))
        XCTAssertEqual(rig.store.forget("ships on fridays"), .success("Ships on Fridays."))
        XCTAssertEqual(rig.store.forget("jazz"), .success("Likes jazz."))
        XCTAssertEqual(rig.store.longTerm!.aboutYou, [])
        XCTAssertEqual(rig.store.longTerm!.preferences, ["Likes it quiet before 10am."])
    }

    func testANewDaySnapshotsAndStartsFresh() throws {
        let rig = try MemoryRig()
        _ = rig.store.note("landing: flaky tests")
        rig.store.apply(.happened("14:05 claude · jetpack · finished (18 min)"))
        rig.store.apply(.newDay(date: "2026-10-15", firstSeen: "09:01"))
        XCTAssertTrue(rig.file("history/2026-10-14/short-term.md").contains("landing: flaky tests"))
        XCTAssertTrue(rig.file("history/2026-10-14/short-term.md").contains("14:05 claude · jetpack"))
        XCTAssertTrue(rig.file("history/2026-10-14/long-term.md").contains("name: Pip"))
        XCTAssertEqual(rig.file("short-term.md"), "## Today\n2026-10-15 · first seen 09:01\n\n## Notes\n\n## Happened\n")
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-15")
    }

    func testHandEditsAreKept() throws {
        let rig = try MemoryRig()
        var edited = rig.file("long-term.md")
        edited = edited.replacingOccurrences(of: "## About you\n", with: "## About you\n- Hand-written line.\n")
        try rig.edit("long-term.md", edited)
        XCTAssertNotNil(try? rig.store.remember("Ships on Fridays.", as: .aboutYou).get())
        XCTAssertEqual(rig.store.longTerm!.aboutYou, ["Hand-written line.", "Ships on Fridays."])
        XCTAssertTrue(rig.file("long-term.md").contains("- Hand-written line.\n- Ships on Fridays.\n"))
    }

    func testABrokenLongTermIsRestoredFromItsSnapshot() throws {
        let rig = try MemoryRig()
        _ = rig.store.remember("Ships on Fridays.", as: .aboutYou)
        rig.store.apply(.newDay(date: "2026-10-15", firstSeen: "09:01"))  // snapshot with the fact
        try rig.edit("long-term.md", "## Boop\nname Pip, hatched some time ago\n")
        XCTAssertTrue(rig.store.longTermText.contains("- Ships on Fridays.\n"))
        XCTAssertTrue(rig.file("long-term.md").contains("- Ships on Fridays.\n"))
        XCTAssertEqual(rig.file("long-term.md.broken"), "## Boop\nname Pip, hatched some time ago\n")
        XCTAssertTrue(rig.logs.contains { $0.contains("restored from history/2026-10-14") })
        // And on a restart.
        try rig.edit("long-term.md", "garbage")
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
    }

    func testABrokenShortTermKeepsItsDate() throws {
        let rig = try MemoryRig()
        try rig.edit("short-term.md", "## Today\n2026-10-14, a lovely day\n## Notes\n")
        try rig.reopen()
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-14")
        XCTAssertTrue(rig.file("short-term.md.broken").contains("a lovely day"))
        try rig.edit("short-term.md", "nothing useful")
        try rig.reopen()
        XCTAssertNil(rig.store.lastActiveDay)
    }

    /// The core's effects land in the files, and a restart that reads
    /// today's date back doesn't start the day twice.
    func testCoreAndMemoryTogether() throws {
        let rig = try MemoryRig(setUp: false)
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let start = CoreRig.start  // 2026-10-14 14:00 UTC
        try rig.store.setUp(name: "Pip", nature: .sweet, seed: 1, today: "2026-10-13")
        rig.store.apply(.newDay(date: "2026-10-13", firstSeen: "09:00"))
        func boot(_ now: Int64) -> (Core, [CoreEffect]) {
            let core = Core(config: .init(name: "Pip", time: time), lastActiveDay: rig.store.lastActiveDay)
            let fx = core.handle(BoopEvent(agent: .claudeCode, session: "s1", project: "landing", event: .turnStart,
                                           detail: .init(), ts: now))
            for effect in fx { rig.store.apply(effect) }
            return (core, fx)
        }
        let (_, first) = boot(start)
        XCTAssertTrue(first.contains { if case .newDay = $0 { true } else { false } })
        XCTAssertTrue(rig.file("history/2026-10-13/short-term.md").contains("2026-10-13"))
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-14")
        try rig.reopen()
        let (_, again) = boot(start + 60_000)
        XCTAssertFalse(again.contains { if case .newDay = $0 { true } else { false } })
    }

    func testLimitsHoldOnHandEditedFiles() throws {
        let rig = try MemoryRig()
        var text = rig.file("long-term.md")
        text = text.replacingOccurrences(of: "## Preferences\n",
                                         with: "## Preferences\n" + (0..<20).map { "- pref \($0)\n" }.joined())
        try rig.edit("long-term.md", text)
        XCTAssertEqual(rig.store.longTerm?.preferences.count, 15)
    }
}

extension StateSnapshot {
    static let sample = StateSnapshot(
        time: 0, name: "Pip", base: "idle", attn: nil, busy: 0, idle: 0, wait: 0, quiet: 0, vol: 6)
}
