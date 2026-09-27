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
        store = try MemoryStore(directory: dir, log: { [weak self] in self?.logs.append($0) })
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
    static let sample = "## Boop\nname: Pip · hatched: 2026-10-02 · nature: cheeky · seed: 7f3a\n"

    func testLongTermRoundTrips() throws {
        let lt = try LongTerm.parse(MemoryTests.sample)
        XCTAssertEqual(lt.name, "Pip")
        XCTAssertEqual(lt.nature, .cheeky)
        XCTAssertEqual(lt.seed, 0x7f3a)
        XCTAssertEqual(lt.markdown, MemoryTests.sample)
    }

    /// Files from before 2026-09-27 have Temperament, Moments, About you and
    /// Preferences in `long-term.md`, and Notes and Happened in
    /// `short-term.md`; older ones a Growth section and a mood on the Today
    /// line. They still load, and the store leaves them as they are until
    /// it next writes.
    func testFilesFromBeforeStillLoad() throws {
        let oldLongTerm = MemoryTests.sample + """

            ### Temperament
            Nosy and a bit smug.

            ### Growth
            xp: 1240 · level: 25 · last fed: 2026-10-14 · lost: 3

            ## About you
            - Ships on Fridays.

            """
        try XCTAssertEqual(try LongTerm.parse(oldLongTerm), try LongTerm.parse(MemoryTests.sample))
        let oldShortTerm = "## Today\n2026-10-14 · first seen 08:52 · mood: a bit frazzled\n\n## Notes\n- a note\n\n## Happened\n- 14:02 codex · landing · failed\n"
        let st = try ShortTerm.parse(oldShortTerm)
        XCTAssertEqual(st, ShortTerm(date: "2026-10-14", firstSeen: "08:52"))

        let rig = try MemoryRig()
        try rig.edit("long-term.md", oldLongTerm)
        try rig.edit("short-term.md", oldShortTerm)
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-14")
        XCTAssertFalse(rig.logs.contains { $0.contains("didn't read") }, "\(rig.logs)")
        XCTAssertEqual(rig.file("long-term.md"), oldLongTerm)
    }

    func testUnreadableFilesThrow() throws {
        try XCTAssertThrowsError(try LongTerm.parse("hello"))
        try XCTAssertThrowsError(try LongTerm.parse(MemoryTests.sample.replacingOccurrences(of: "seed: 7f3a", with: "seed: lots")))
        try XCTAssertThrowsError(try LongTerm.parse(MemoryTests.sample.replacingOccurrences(of: "nature: cheeky", with: "nature: grumpy")))
        try XCTAssertThrowsError(try ShortTerm.parse("## Today\nyesterday\n"))
        try XCTAssertThrowsError(try ShortTerm.parse("## Today\n2026-02-30 · first seen 08:00\n"))
    }

    func testSetUpWritesLongTermAndASnapshot() throws {
        let rig = try MemoryRig()
        XCTAssertEqual(rig.file("long-term.md"), MemoryTests.sample)
        XCTAssertTrue(rig.file("history/2026-10-02/long-term.md").contains("name: Pip"))
        try XCTAssertThrowsError(try rig.store.setUp(name: "Bo", nature: .sweet, seed: 1, today: "2026-10-14"))
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-14")
        XCTAssertEqual(Dialect(seed: rig.store.longTerm!.seed), Dialect(seed: 0x7f3a))
    }

    func testNamesThatBreakTheBoopLineAreRefused() throws {
        let rig = try MemoryRig(setUp: false)
        try XCTAssertThrowsError(try rig.store.setUp(name: "Pip · xp: 9", nature: .sweet, seed: 1, today: "2026-10-14"))
        try XCTAssertThrowsError(try rig.store.setUp(name: "", nature: .sweet, seed: 1, today: "2026-10-14"))
        XCTAssertFalse(rig.store.isSetUp)
    }

    func testOnlyANewDayChangesTheFiles() throws {
        let rig = try MemoryRig()
        let before = (rig.file("long-term.md"), rig.file("short-term.md"))
        rig.store.apply(.state(StateSnapshot.sample))
        rig.store.apply(.moment(anim: "cheer"))
        XCTAssertEqual(rig.file("long-term.md"), before.0)
        XCTAssertEqual(rig.file("short-term.md"), before.1)
    }

    func testANewDaySnapshotsAndStartsFresh() throws {
        let rig = try MemoryRig()
        rig.store.apply(.newDay(date: "2026-10-15", firstSeen: "09:01"))
        XCTAssertTrue(rig.file("history/2026-10-14/short-term.md").contains("2026-10-14 · first seen 08:52"))
        XCTAssertTrue(rig.file("history/2026-10-14/long-term.md").contains("name: Pip"))
        XCTAssertEqual(rig.file("short-term.md"), "## Today\n2026-10-15 · first seen 09:01\n")
        XCTAssertEqual(rig.store.lastActiveDay, "2026-10-15")
    }

    func testHandEditsAreReadAgain() throws {
        let rig = try MemoryRig()
        try rig.edit("long-term.md", MemoryTests.sample.replacingOccurrences(of: "name: Pip", with: "name: Pippa"))
        XCTAssertEqual(rig.store.longTerm?.name, "Pippa")
    }

    func testABrokenLongTermIsRestoredFromItsSnapshot() throws {
        let rig = try MemoryRig()
        try rig.edit("long-term.md", "## Boop\nname Pip, hatched some time ago\n")
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
        XCTAssertEqual(rig.file("long-term.md"), MemoryTests.sample)
        XCTAssertEqual(rig.file("long-term.md.broken"), "## Boop\nname Pip, hatched some time ago\n")
        XCTAssertTrue(rig.logs.contains { $0.contains("restored from history/2026-10-02") })
        // And on a restart.
        try rig.edit("long-term.md", "garbage")
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
    }

    func testABrokenShortTermKeepsItsDate() throws {
        let rig = try MemoryRig()
        try rig.edit("short-term.md", "## Today\n2026-10-14, a lovely day\n")
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

}

extension StateSnapshot {
    static let sample = StateSnapshot(
        time: 0, name: "Pip", base: "idle", attn: nil, busy: 0, idle: 0, wait: 0, quiet: 0, vol: 6)
}
