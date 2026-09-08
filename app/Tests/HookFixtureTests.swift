import Foundation
import XCTest
@testable import BoopCore

final class HookFixtureTests: XCTestCase {
    /// Replay the raw captures so an agent's schema drift fails at the input boundary.
    func testRecordedHooksDecode() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/hooks")
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in files {
            guard file.pathExtension == "json" else { continue }
            let body = try JSONDecoder().decode(HookEventBody.self, from: Data(contentsOf: file))
            XCTAssertNotNil(body.effectiveEventName, file.path)
            XCTAssertNotNil(body.session_id ?? body.conversation_id, file.path)
        }
    }
}
