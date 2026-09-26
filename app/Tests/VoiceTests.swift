import Foundation
import XCTest
@testable import BoopKit

final class VoiceTests: XCTestCase {
    func testTheSetIsFixedAndAvoidsHardSounds() {
        XCTAssertEqual(Sounds.all.count, 64)
        XCTAssertEqual(Set(Sounds.all).count, 64)
        for s in Sounds.all {
            for bad in ["s", "f", "r", "v", "h"] { XCTAssertFalse(s.contains(bad), s) }
        }
        XCTAssertEqual(Sounds.vocabulary.count, 40)
        XCTAssertEqual(Set(Sounds.vocabulary).count, 40)
        for topic in ["tests", "build", "docs", "deploy", "bug"] { XCTAssertTrue(Sounds.vocabulary.contains(topic)) }
        // The device keeps the word in a 24-byte field and splits syllables on spaces and hyphens.
        for w in Sounds.vocabulary { XCTAssertTrue(w.utf8.count < 24 && !w.contains("-") && !w.contains(" "), w) }
    }

    func testTheDialectComesFromTheSeedAndNeverChanges() {
        let a = Dialect(seed: 0x7f3a)
        XCTAssertEqual(a.favourites.count, 16)
        XCTAssertEqual(Set(a.favourites).count, 16)
        XCTAssertEqual(a, Dialect(seed: 0x7f3a))
        XCTAssertNotEqual(a.favourites, Dialect(seed: 0x7f3b).favourites)
        for s in a.favourites { XCTAssertTrue(Sounds.set.contains(s)) }
    }

    func testLinesAreDeterministic() {
        let voice = Voice(dialect: Dialect(seed: 0x7f3a))
        for feeling in Feeling.allCases {
            for seed in UInt64(1)...20 {
                XCTAssertEqual(voice.line(feeling, word: "done", seed: seed), voice.line(feeling, word: "done", seed: seed))
            }
        }
        XCTAssertNotEqual(voice.line(.happy, seed: 1), voice.line(.happy, seed: 2))
    }

    func testLineShape() {
        let voice = Voice(dialect: Dialect(seed: 42))
        for feeling in Feeling.allCases {
            for seed in UInt64(1)...200 {
                let line = voice.line(feeling, word: seed % 2 == 0 ? "tests" : nil, seed: seed)
                XCTAssertEqual(line.tune, line.isSafeHum ? .down : feeling.tune)
                XCTAssertTrue((2...8).contains(line.syllableCount), line.syl)
                for g in line.groups { XCTAssertTrue((1...3).contains(g.count), line.syl) }
                for s in line.groups.joined() { XCTAssertTrue(Sounds.set.contains(s), s) }
                XCTAssertTrue((90...180).contains(line.ms))
                if let word = line.word {
                    XCTAssertEqual(word, "tests")
                    XCTAssertTrue(line.at == 0 || line.at == line.syllableCount)
                }
            }
        }
    }

    func testFeelingsShapeTheSyllables() {
        let voice = Voice(dialect: Dialect(seed: 9))
        for seed in UInt64(1)...100 {
            let happy = voice.line(.happy, seed: seed)
            if !happy.isSafeHum {
                for s in happy.groups.joined() { XCTAssertTrue("ai".contains(Sounds.vowel(s)!), s) }
            }
            let annoyed = voice.line(.annoyed, seed: seed)
            if !annoyed.isSafeHum {
                for s in annoyed.groups.joined() { XCTAssertTrue("tkp".contains(s.first!), s) }
            }
            let curious = voice.line(.curious, word: "tests", seed: seed)
            XCTAssertEqual(curious.at, curious.syllableCount)
            if !curious.isSafeHum { XCTAssertTrue("ie".contains(curious.groups.last!.last!.last!)) }
            let sad = voice.line(.sad, seed: seed)
            if !sad.isSafeHum { XCTAssertTrue(["u", "o"].contains(sad.groups.last!.last!)) }
        }
        // Excited talks faster and longer than sleepy.
        let excited = (UInt64(1)...200).map { voice.line(.excited, seed: $0) }
        let sleepy = (UInt64(1)...200).map { voice.line(.sleepy, seed: $0) }
        XCTAssertGreaterThan(excited.map(\.syllableCount).reduce(0, +), sleepy.map(\.syllableCount).reduce(0, +))
        XCTAssertLessThan(excited[0].ms, sleepy[0].ms)
    }

    /// VOICE.md §5: tempo starts from the neutral pace (135 ms a syllable)
    /// and moves only with the feeling; there's no mood.
    func testTempoIsNeutralThenByFeeling() {
        let ms = Dictionary(uniqueKeysWithValues: Feeling.allCases.map { ($0, Voice.tempo($0)) })
        XCTAssertEqual(ms, [.proud: 135, .curious: 135, .excited: 115, .happy: 125, .annoyed: 125, .hopeful: 145,
                            .sad: 160, .sleepy: 170])
        XCTAssertEqual(Voice(dialect: Dialect(seed: 1)).line(.proud, seed: 3).ms, 135)
    }

    func testAWordOutsideTheVocabularyIsLeftOut() {
        let voice = Voice(dialect: Dialect(seed: 1))
        XCTAssertNil(voice.line(.happy, word: "kubernetes", seed: 1).word)
    }

    func testTheCheckCatchesWords() throws {
        let check = Unintelligible.shared
        try XCTSkipUnless(check.hasDictionary, "no /usr/share/dict/words")
        XCTAssertNotNil(check.failure([["ba", "na", "na"]]))  // Minion and English
        XCTAssertNotNil(check.failure([["ba", "ka"]]))  // rude in Japanese
        XCTAssertNotNil(check.failure([["to", "ma", "to"]]))  // English
        XCTAssertNotNil(check.failure([["pi"], ["ba", "ka"], ["lo"]]))  // rude inside the line
        XCTAssertNotNil(check.failure([["be"], ["do"]]))  // the whole line reads "bedo"
        XCTAssertNil(check.failure([["mi", "po"], ["lu"]]))
        // VOICE.md §7: only words spelled with Boop's letters are kept,
        // lowercased, since no other word can match gibberish.
        XCTAssertTrue(check.words.contains("tomato"))
        XCTAssertTrue(check.words.contains("bob"), "a name, lowercased")
        XCTAssertFalse(check.words.contains("cat"), "c isn't one of Boop's letters")
        XCTAssertFalse(check.words.contains { $0.count < 3 })
    }

    /// VOICE.md §7 and PLAN.md A2: 10,000 lines, zero hits in the word list
    /// or the rude and Minion lists, checked independently of Voice's own check.
    func testTenThousandLinesSayNothing() throws {
        let words = Set(((try? String(contentsOfFile: Unintelligible.dictionaryPath, encoding: .utf8)) ?? "")
            .split(whereSeparator: \.isNewline).filter { $0.count >= 3 }.map { $0.lowercased() })
        try XCTSkipUnless(!words.isEmpty, "no /usr/share/dict/words")
        let banned = Unintelligible.rude.union(Unintelligible.minion)
        var hits: [String] = []
        var hums = 0
        var n = 0
        var doublesInWordList = 0
        var lengths = 0
        for dialectSeed in UInt64(1)...25 {
            let voice = Voice(dialect: Dialect(seed: dialectSeed &* 7919))
            for i in 0..<400 {
                let feeling = Feeling.allCases[i % Feeling.allCases.count]
                let line = voice.line(feeling, word: i % 3 == 0 ? Sounds.vocabulary[i % 40] : nil, seed: UInt64(i + 1))
                n += 1
                if line.isSafeHum { hums += 1 }
                // Doubles (`ki-ki`) skip the big word list but not the common
                // doubles (VOICE.md §7).
                for g in line.groups {
                    let w = g.joined()
                    let doubled = g.count == 2 && g[0] == g[1]
                    if (!doubled && w.count >= 3 && words.contains(w)) || banned.contains(w)
                        || Unintelligible.commonDoubles.contains(w) {
                        hits.append("\(line.syl) → \(w)")
                    }
                    if doubled && words.contains(w) { doublesInWordList += 1 }
                }
                let whole = line.groups.map { $0.joined() }.joined()
                if line.groups.count > 1 && (words.contains(whole) || banned.contains(whole)) {
                    hits.append("\(line.syl) → \(whole)")
                }
                for bad in banned where bad.count >= 4 && whole.contains(bad) { hits.append("\(line.syl) ⊃ \(bad)") }
                lengths += line.syllableCount
            }
        }
        XCTAssertEqual(n, 10_000)
        XCTAssertEqual(hits, [])
        // The safe hum is a last resort, not a habit.
        XCTAssertLessThan(hums, 50)
        print("  10,000 lines: \(hums) safe hums, \(lengths) syllables, \(doublesInWordList) doubles found in the word list")
    }

    func testMomentJSON() {
        let line = VoiceLine(groups: [["bi", "do"], ["ba", "na"]], word: "done", at: 4, tune: .up, ms: 120)
        XCTAssertEqual(DeviceMoment(say: line).jsonLine,
                       #"{"t":"moment","say":{"syl":"bi-do ba-na","word":"done","at":4,"tune":"up","ms":120},"ttl":5}"#)
        let plain = VoiceLine(groups: [["mm", "nn"]], word: nil, at: 2, tune: .down, ms: 170)
        XCTAssertEqual(plain.json, #"{"syl":"mm-nn","tune":"down","ms":170}"#)
    }
}
