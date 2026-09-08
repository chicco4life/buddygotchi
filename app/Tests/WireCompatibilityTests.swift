import Foundation
import XCTest
@testable import BoopCore

final class WireCompatibilityTests: XCTestCase {
    func testV2FixtureAndNoLegacyKeys() throws {
        let legacy = #"{"pet":"busy","species":"blob","celebrate":false,"promptId":"r1","msg":"working","entries":[],"sessions":[]}"#
        let v2 = #"{"v":2,"state":"working","effort":"hard","dots":1,"gift":false,"focus":false,"mute":1,"t":123}"#
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any])
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(v2.utf8)) as? NSDictionary)
        let frame = RenderState(state: .working, effort: .hard, dots: 1, t: 123)
        let encoded = try JSONEncoder().encode(frame)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        XCTAssertEqual(object, fixture)
        for key in old.keys { XCTAssertNil(object[key], key) }
    }

    func testNewAndLegacyInboundFixtures() throws {
        for line in [#"{"cmd":"decision","id":"r1","d":"allow"}"#, #"{"cmd":"permission","id":"r1","decision":"allow"}"#] {
            guard case let .decision(id, d) = try XCTUnwrap(parseDeviceLine(line)) else { throw NSError(domain: "decision expected", code: 1) }
            XCTAssertEqual(id, "r1")
            XCTAssertEqual(d, .allow)
        }
        for line in [#"{"cmd":"boop"}"#, #"{"cmd":"boop","hold":false}"#] {
            guard case .boop(hold: false) = try XCTUnwrap(parseDeviceLine(line)) else { throw NSError(domain: "boop expected", code: 1) }
        }
        for line in [#"{"cmd":"collect"}"#, #"{"cmd":"posture","p":"travel"}"#, #"{"cmd":"motion","m":"pickup"}"#, #"{"cmd":"battery","pct":40,"charging":true}"#, #"{"cmd":"focus","on":false}"#, #"{"ack":"ota","ok":true}"#, #"{"cmd":"status","board":"ws-amoled164","contract":2}"#] {
            XCTAssertNotNil(parseDeviceLine(line), line)
        }
    }

    func testMalformedCommandsRejected() {
        for line in ["no", "[]", #"{"cmd":"decision","id":"r","d":"oops"}"#, #"{"cmd":"permission","id":"r","decision":"passthrough"}"#, #"{"cmd":"boop","hold":1}"#, #"{"cmd":"focus","on":1}"#, #"{"cmd":"battery","pct":101,"charging":true}"#, #"{"cmd":"battery","pct":1.5,"charging":true}"#, #"{"cmd":"posture","p":"unknown"}"#, #"{"cmd":"motion","m":"unknown"}"#] {
            XCTAssertNil(parseDeviceLine(line), line)
        }
    }
}
