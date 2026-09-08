import Foundation
import XCTest
@testable import BoopCore

final class ReflectionTests: XCTestCase {
    func testRulesFromDayMaxFiveAndIdempotentRerun() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let store = try Store(stateDir:dir.path,now:0)
        var facts: [StoredFact] = []
        for d in 1...5 {
            let day = String(format:"2026-01-%02d",d)
            for project in ["a","b","c","d"] {
                facts.append(StoredFact(fact:.project(id:project),sessionId:project,project:project,at:Double(d),day:day))
            }
            facts.append(StoredFact(fact:.moment(.lateNight),sessionId:"a",project:"a",at:Double(d),day:day))
            for project in ["a","b","c"] {
                facts.append(StoredFact(fact:.activity(hour:1,tool:"Bash",firstGoal:"swift-test"),sessionId:project,project:project,at:Double(d),day:day))
                facts.append(StoredFact(fact:.goalOutcome(goalKey:"hash",runner:"swift-test",outcome:.pass,attempts:1,elapsedMs:1),sessionId:project,project:project,at:Double(d),day:day))
            }
        }
        try await store.appendFacts(facts)
        let lines = try await store.reflect(localDay:"2026-01-05",at:5)
        XCTAssertEqual(lines.map(\.line),["tests first, usually","works late","reaches for swift-test","keeps coming back to a","keeps coming back to b"])
        let traits = try await store.traits()
        let rerun = try await store.reflect(localDay:"2026-01-05",at:6)
        XCTAssertEqual(rerun,lines)
        let repeatTraits = try await store.traits(); XCTAssertEqual(repeatTraits,traits)
        var next = facts.filter { $0.day == "2026-01-05" }
        for i in next.indices { next[i].day = "2026-01-06"; next[i].at = 6 }
        try await store.appendFacts(next)
        let repeatLines = try await store.reflect(localDay:"2026-01-06",at:6)
        XCTAssertEqual(repeatLines.count,5)
        XCTAssertTrue(repeatLines.allSatisfy { $0.confidence > 0.6 })
    }
    func testTestsFirstRequiresFirstToolAndSixtyPercent() {
        let facts = (0..<5).map { i in StoredFact(fact:.activity(hour:10,tool:"Bash",firstGoal:i < 3 ? "pytest" : "none"),sessionId:String(i),project:"p",at:0,day:"2026-01-01") }
        XCTAssertTrue(Reflection.candidates(day:facts,history:facts,localDay:"2026-01-01").contains("tests first, usually"))
        var fewer = facts; fewer[0].fact = .activity(hour:10,tool:"Read",firstGoal:"none")
        XCTAssertFalse(Reflection.candidates(day:fewer,history:fewer,localDay:"2026-01-01").contains("tests first, usually"))
    }
    func testDailyDriftUsesStructuredSignals() {
        let inputs: [Fact] = [.activity(hour:8,tool:nil,firstGoal:nil),.sessionSummary(turns:20,tasks:1,elapsedMs:100),.moment(.lateNight),.denial,.moment(.nthRateLimit),.checkIn(collected:false),.greet,.project(id:"new")]
        let facts = inputs.map { StoredFact(fact:$0,sessionId:"s",project:"new",at:0,day:"2026-01-01") }
        XCTAssertEqual(DailyDrift.calculate(facts,history:facts),["energy":1,"cheek":2,"warmth":2,"curiosity":1])
    }
}
