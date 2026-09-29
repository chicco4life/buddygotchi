import Foundation
import XCTest
@testable import BoopKit

extension Take {
    /// A real take by id, for tests.
    static func named(_ id: String) -> Take { Take.all.first { $0.id == id }! }
}

extension DeviceMoment.Say {
    /// Excited's "Go" (new.d02), 770 ms: a real take for tests.
    static let go = DeviceMoment.Say(take: .named("new.d02"))

    /// A made-up take `ms` long, for tests that time a line.
    static func test(ms: Int) -> DeviceMoment.Say {
        .init(take: Take(id: "test", text: "Test", meaning: "begin", kind: .word, mood: "calm", finish: nil, ms: ms))
    }
}

final class VoiceTests: XCTestCase {
    /// VOICE.md §3: every take is in one of the 13 moods, means something
    /// `say.meaning` offers (or only the rules say it), and has a length
    /// and text the bubble can show; ids are unique.
    func testEveryTakeIsUsable() {
        let moods = Set(MoodAction.moods.map(\.name))
        let meanings = Set(ReactAction.meanings.map(\.name)).union(Voice.rulesOnly)
        XCTAssertEqual(Take.all.count, 40)
        XCTAssertEqual(Set(Take.all.map(\.id)).count, Take.all.count)
        for t in Take.all {
            XCTAssertTrue(moods.contains(t.mood), "\(t.id) is in \(t.mood)")
            XCTAssertTrue(meanings.contains(t.meaning), "\(t.id) means \(t.meaning), which say.meaning doesn't offer")
            XCTAssertTrue((300...3000).contains(t.ms), "\(t.id) is \(t.ms) ms")
            XCTAssertTrue(!t.text.isEmpty && t.text.utf8.count <= 20 && t.text.allSatisfy { $0.isASCII }, t.text)
            XCTAssertTrue(t.finish == nil || ["success", "failure"].contains(t.finish!), t.id)
        }
        // Swears only on a failure (VOICE.md §4).
        XCTAssertTrue(Take.all.filter { $0.kind == .swear }.allSatisfy { $0.finish == "failure" })
    }

    /// The board has the same takes as the Mac's table: both come from
    /// voicegen, and a take the board doesn't have plays nothing.
    func testTheBoardHasEveryTake() throws {
        let header = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../firmware/assets/voice.h")
        let text = try String(contentsOf: header, encoding: .utf8)
        let rows = text.components(separatedBy: "\n").filter { $0.hasPrefix("    {\"") }
        let ids = rows.compactMap { $0.split(separator: "\"").dropFirst().first.map(String.init) }
        XCTAssertEqual(ids, Take.all.map(\.id))
    }

    /// VOICE.md §4: a take of the meaning, in the face's mood only.
    func testATakeIsOnlyEverTheFacesMood() {
        let voice = Voice()
        var rng = SplitMix64(seed: 1)
        for face in MoodAction.moods.map(\.name) {
            for meaning in voice.meanings {
                for kind in Take.Kind.allCases {
                    for finish in [nil, "success", "failure"] {
                        guard let t = voice.take(meaning: meaning, kind: kind, face: face, finish: finish, avoiding: nil, rng: &rng)
                        else { continue }
                        XCTAssertEqual(t.mood, face)
                        XCTAssertEqual(t.meaning, meaning)
                        XCTAssertTrue(t.finish == nil || t.finish == finish, "\(t.id) needs a \(t.finish!)")
                        XCTAssertLessThanOrEqual(Take.Kind.allCases.firstIndex(of: t.kind)!, Take.Kind.allCases.firstIndex(of: kind)!)
                    }
                }
            }
        }
        // Calm has no frustration take, nor wounded any celebration: silence.
        XCTAssertNil(voice.take(meaning: "frustration", kind: .word, face: "calm", finish: "failure", avoiding: nil, rng: &rng))
        XCTAssertNil(voice.take(meaning: "celebrate", kind: .word, face: "wounded", finish: "success", avoiding: nil, rng: &rng))
    }

    /// VOICE.md §4: a success take only on a success, a swear only on a
    /// failure.
    func testTheFinishGatesSuccessesAndSwears() {
        let voice = Voice()
        var rng = SplitMix64(seed: 2)
        XCTAssertNil(voice.take(meaning: "success", kind: .word, face: "happy", finish: nil, avoiding: nil, rng: &rng))
        XCTAssertNil(voice.take(meaning: "success", kind: .word, face: "happy", finish: "failure", avoiding: nil, rng: &rng))
        XCTAssertEqual(voice.take(meaning: "success", kind: .word, face: "happy", finish: "success", avoiding: nil, rng: &rng)?.finish,
                       "success")
        // A grumpy swear at a failed turn; with no failure, the phrase.
        XCTAssertEqual(voice.take(meaning: "frustration", kind: .swear, face: "grumpy", finish: "failure", avoiding: nil, rng: &rng)?.kind,
                       .swear)
        XCTAssertEqual(voice.take(meaning: "frustration", kind: .swear, face: "grumpy", finish: nil, avoiding: nil, rng: &rng)?.id,
                       "new.d14")
    }

    /// VOICE.md §4: with none of the kind asked for, the next plainer kind
    /// that has one; never a fancier one.
    func testKindStepsDownNeverUp() {
        let voice = Voice()
        var rng = SplitMix64(seed: 3)
        // Happy celebrates only in words: a phrase asked for says a word.
        XCTAssertEqual(voice.take(meaning: "celebrate", kind: .phrase, face: "happy", finish: "success", avoiding: nil, rng: &rng)?.kind,
                       .word)
        // Excited celebrates only in a phrase: a word asked for says nothing.
        XCTAssertNil(voice.take(meaning: "celebrate", kind: .word, face: "excited", finish: "success", avoiding: nil, rng: &rng))
        XCTAssertEqual(voice.take(meaning: "celebrate", kind: .phrase, face: "excited", finish: "success", avoiding: nil, rng: &rng)?.id,
                       "new.d15")
    }

    /// VOICE.md §4: the last take said isn't said again while another fits.
    func testTheLastTakeIsntRepeated() {
        let voice = Voice()
        var rng = SplitMix64(seed: 4)
        for _ in 0..<50 {
            let t = voice.take(meaning: "frustration", kind: .sound, face: "annoyed", finish: nil, avoiding: "previous.tsk", rng: &rng)
            XCTAssertEqual(t?.id, "previous.pfft")
        }
        // With only one that fits, it's said again.
        XCTAssertEqual(voice.take(meaning: "ponder", kind: .sound, face: "curious", finish: nil, avoiding: "previous.eh", rng: &rng)?.id,
                       "previous.eh")
    }

    /// Needs you's takes are the rules', so no reaction says them.
    func testNoReactionSaysNeedsYousTakes() {
        let voice = Voice()
        var rng = SplitMix64(seed: 5)
        XCTAssertFalse(voice.meanings.contains("attention"))
        XCTAssertNil(voice.take(meaning: "attention", kind: .word, face: "curious", finish: nil, avoiding: nil, rng: &rng))
    }
}
