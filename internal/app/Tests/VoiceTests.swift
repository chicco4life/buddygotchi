import Foundation
import XCTest
@testable import BoopKit

extension Take {
    /// A real take by id, for tests.
    static func named(_ id: String) -> Take { Take.all.first { $0.id == id }! }
}

extension DeviceMoment.Say {
    /// Excited's "Go" (new.d02): a real take for tests.
    static let go = DeviceMoment.Say(takes: [.named("new.d02")])

    /// A made-up take `ms` long, for tests that time a line.
    static func test(ms: Int) -> DeviceMoment.Say {
        .init(takes: [Take(id: "test", text: "Test", part: .about, meaning: "start", kind: .word, mood: "calm", finish: nil, ms: ms)])
    }
}

final class VoiceTests: XCTestCase {
    let moods = MoodAction.moods.map(\.name)

    /// VOICE.md §3: every take is in one of the 13 moods, answers a
    /// question the react action asks (or only the rules say it), and has
    /// a length and text the bubble can show; ids are unique.
    func testEveryTakeIsUsable() {
        let feelings = Set(ReactAction.feelings.map(\.name)), topics = Set(ReactAction.topics.map(\.name))
        XCTAssertEqual(Take.all.count, 2722)
        XCTAssertEqual(Set(Take.all.map(\.id)).count, Take.all.count)
        for t in Take.all {
            XCTAssertTrue(moods.contains(t.mood), "\(t.id) is in \(t.mood)")
            switch t.part {
            case .feeling: XCTAssertTrue(feelings.contains(t.meaning), "\(t.id) feels \(t.meaning), which say.feeling doesn't offer")
            case .about: XCTAssertTrue(topics.contains(t.meaning), "\(t.id) is about \(t.meaning), which say.about doesn't offer")
            case .attention: XCTAssertEqual(t.meaning, "attention")
            }
            XCTAssertTrue((300...3000).contains(t.ms), "\(t.id) is \(t.ms) ms")
            XCTAssertTrue(!t.text.isEmpty && t.text.utf8.count <= 35 && t.text.allSatisfy { $0.isASCII }, t.text)
            XCTAssertTrue(t.finish == nil || ["success", "failure"].contains(t.finish!), t.id)
        }
        // Swears only on a failure, and only as a feeling (VOICE.md §4, §6).
        XCTAssertTrue(Take.all.filter { $0.kind == .swear }.allSatisfy { $0.finish == "failure" && $0.part == .feeling })
        XCTAssertEqual(Take.packVersion.count, 12)
    }

    /// The owner's rule (VOICE.md §3): every face has a take for every
    /// feeling and every topic. Every feeling has one that plays whatever
    /// the finish, but glad in a bad mood, which is only relief at a
    /// success.
    func testNoFaceIsWithoutWords() {
        let voice = Voice()
        let bad: Set = ["annoyed", "irritated", "grumpy", "whiny", "wounded", "sad"]
        for (part, answers) in [(Take.Part.feeling, ReactAction.feelings), (.about, ReactAction.topics)] {
            for a in answers.map(\.name) {
                XCTAssertEqual(voice.faces(saying: a, part: part, in: moods), moods, "\(part) \(a)")
                for face in moods where part == .feeling && !(a == "glad" && bad.contains(face)) {
                    XCTAssertTrue(voice.takes.contains { $0.part == part && $0.meaning == a && $0.mood == face && $0.finish == nil },
                                  "\(face) \(a) says nothing unless the turn finished")
                }
            }
        }
    }

    /// The takes the board plays are the Mac's: voicegen writes both, and
    /// the board reports the pack's version (PROTOCOL.md §5).
    func testThePackHasEveryTake() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../.build/voice/voice.bin")
        let pack = try Data(contentsOf: url)
        XCTAssertEqual(pack.prefix(8), Data("BOOPVOX1".utf8))
        let version = String(decoding: pack[8..<24].prefix { $0 != 0 }, as: UTF8.self)
        XCTAssertEqual(version, Take.packVersion, "rerun voicegen")
        func u32(_ at: Int) -> Int { pack[at..<at + 4].enumerated().reduce(0) { $0 | Int($1.1) << (8 * $1.0) } }
        let count = u32(24), size = u32(28), index = u32(32)
        let ids = (0..<count).map { i in String(decoding: pack[(index + i * size)...].prefix(72).prefix { $0 != 0 }, as: UTF8.self) }
        XCTAssertEqual(ids, Take.all.map(\.id).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    }

    /// VOICE.md §4: a take of the answer, in the face's mood only, fit for
    /// the finish.
    func testATakeIsOnlyEverTheFacesMood() {
        let voice = Voice()
        var rng = SplitMix64(seed: 1)
        for face in moods {
            for (part, answers) in [(Take.Part.feeling, voice.answers(.feeling)), (.about, voice.answers(.about))] {
                for a in answers {
                    for kind in Take.Kind.allCases {
                        for finish in [nil, "success", "failure"] {
                            guard let t = voice.take(part, meaning: a, kind: kind, face: face, finish: finish, rng: &rng) else { continue }
                            XCTAssertEqual(t.mood, face)
                            XCTAssertEqual(t.meaning, a)
                            XCTAssertEqual(t.part, part)
                            XCTAssertTrue(t.finish == nil || t.finish == finish, "\(t.id) needs a \(t.finish!)")
                            XCTAssertTrue(t.kind != .swear || kind == .swear, "\(t.id): a swear nobody asked for")
                        }
                    }
                }
            }
        }
    }

    /// VOICE.md §4: a success take only on a success, a swear only on a
    /// failed turn.
    func testTheFinishGatesSuccessesAndSwears() {
        let voice = Voice()
        var rng = SplitMix64(seed: 2)
        // Grumpy is glad only with relief, at a success.
        XCTAssertNil(voice.take(.feeling, meaning: "glad", kind: .sound, face: "grumpy", finish: nil, rng: &rng))
        XCTAssertEqual(voice.take(.feeling, meaning: "glad", kind: .sound, face: "grumpy", finish: "success", rng: &rng)?.finish, "success")
        // Irritated swears at a failed turn; with no failure, the nearest
        // plainer kind: a phrase.
        XCTAssertEqual(voice.take(.feeling, meaning: "upset", kind: .swear, face: "irritated", finish: "failure", rng: &rng)?.kind, .swear)
        XCTAssertEqual(voice.take(.feeling, meaning: "upset", kind: .swear, face: "irritated", finish: nil, rng: &rng)?.kind, .phrase)
        // "Passed" is about tests, and only at a success.
        XCTAssertFalse(voice.takes.contains { $0.text == "Passed" && ($0.meaning != "tests" || $0.finish != "success") })
    }

    /// VOICE.md §4: with none of the kind asked for, the nearest kind,
    /// plainer first; never a swear nobody asked for.
    func testKindTakesTheNearest() {
        XCTAssertEqual(Voice.order(.sound), [.sound, .word, .phrase])
        XCTAssertEqual(Voice.order(.word), [.word, .sound, .phrase])
        XCTAssertEqual(Voice.order(.phrase), [.phrase, .word, .sound])
        XCTAssertEqual(Voice.order(.swear), [.swear, .phrase, .word, .sound])
        let voice = Voice()
        var rng = SplitMix64(seed: 3)
        // Tickled has no sounds: a sound asked for says a word.
        XCTAssertEqual(voice.take(.feeling, meaning: "tickled", kind: .sound, face: "calm", finish: nil, rng: &rng)?.kind, .word)
        // Happy's glad words need a success: without one, a sound.
        XCTAssertEqual(voice.take(.feeling, meaning: "glad", kind: .word, face: "happy", finish: nil, rng: &rng)?.kind, .sound)
    }

    /// VOICE.md §4: the last line's takes aren't said again while another
    /// fits.
    func testTheLastTakesArentRepeated() {
        let voice = Voice()
        var rng = SplitMix64(seed: 4)
        let sounds = voice.takes.filter { $0.part == .feeling && $0.meaning == "upset" && $0.mood == "annoyed" && $0.kind == .sound }
        let avoiding = Set(sounds.dropLast().map(\.id))
        for _ in 0..<50 {
            XCTAssertEqual(voice.take(.feeling, meaning: "upset", kind: .sound, face: "annoyed", finish: nil, avoiding: avoiding, rng: &rng)?.id,
                           sounds.last?.id)
        }
        // With every one avoided, one is said anyway.
        XCTAssertNotNil(voice.take(.feeling, meaning: "upset", kind: .sound, face: "annoyed", finish: nil,
                                   avoiding: Set(sounds.map(\.id)), rng: &rng))
    }

    /// VOICE.md §4: the feeling, then the topic; a phrase alone; and a pair
    /// no longer than `maxLineMs`.
    func testALineIsTheFeelingThenTheTopic() {
        let voice = Voice()
        var rng = SplitMix64(seed: 5)
        for _ in 0..<50 {
            let line = voice.line(feeling: "upset", about: "tests", kind: .sound, face: "annoyed", finish: nil, rng: &rng)
            XCTAssertFalse(line.isEmpty)
            XCTAssertEqual(line[0].part, .feeling)
            if line.count == 2 {
                XCTAssertEqual(line[1].part, .about)
                XCTAssertEqual(line[1].meaning, "tests")
                XCTAssertLessThanOrEqual(DeviceMoment.Say(takes: line).ms, Voice.maxLineMs)
            }
            XCTAssertLessThanOrEqual(line.count, 2)
        }
        // A phrase plays alone.
        let phrase = voice.line(feeling: "upset", about: "tests", kind: .phrase, face: "grumpy", finish: nil, rng: &rng)
        XCTAssertEqual(phrase.map(\.kind), [.phrase])
        // Only a topic: its take alone.
        let topic = voice.line(feeling: nil, about: "tests", kind: .sound, face: "calm", finish: nil, rng: &rng)
        XCTAssertEqual(topic.map(\.part), [.about])
        XCTAssertEqual(voice.line(feeling: nil, about: nil, kind: .sound, face: "calm", finish: nil, rng: &rng), [])
        // Two takes on the wire, and the gap between them in its length.
        let two = DeviceMoment.Say(takes: [.named("previous.tsk"), .named("phase1.word.test.test__annoyed__contained")])
        XCTAssertEqual(two.json, #"{"take":"previous.tsk","then":"phase1.word.test.test__annoyed__contained"}"#)
        XCTAssertEqual(two.ms, two.takes[0].ms + Voice.joinGapMs + two.takes[1].ms)
        XCTAssertEqual(two.text, "Tsk... Test")
    }

    /// Needs you's takes are the rules', so no reaction says them.
    func testNoReactionSaysNeedsYousTakes() {
        let voice = Voice()
        var rng = SplitMix64(seed: 6)
        XCTAssertFalse(voice.answers(.feeling).union(voice.answers(.about)).contains("attention"))
        XCTAssertNil(voice.take(.attention, meaning: "attention", kind: .word, face: "curious", finish: nil, rng: &rng))
    }
}
