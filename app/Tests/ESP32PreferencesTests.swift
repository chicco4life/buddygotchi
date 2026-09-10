import Foundation
import XCTest
@testable import BoopCore

final class ESP32PreferencesTests: XCTestCase {
    @MainActor func testSavedDeviceAndUnpairUseOnlyInjectedPreferences() throws {
        let suite = "device-preferences-" + UUID().uuidString
        let otherSuite = suite + "-other"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let other = try XCTUnwrap(UserDefaults(suiteName: otherSuite))
        defer { defaults.removePersistentDomain(forName: suite); other.removePersistentDomain(forName: otherSuite) }
        let id = UUID(), otherID = UUID()
        defaults.set(id.uuidString, forKey: DefaultsKey.esp32PeripheralUUID)
        other.set(otherID.uuidString, forKey: DefaultsKey.esp32PeripheralUUID)
        let output = ESP32Output(defaults: defaults)
        XCTAssertEqual(output.savedPeripheralIdentifier, id)
        output.unpair()
        XCTAssertNil(output.savedPeripheralIdentifier)
        XCTAssertNil(defaults.object(forKey: DefaultsKey.esp32PeripheralUUID))
        XCTAssertEqual(other.string(forKey: DefaultsKey.esp32PeripheralUUID), otherID.uuidString)
        defaults.set("invalid", forKey: DefaultsKey.esp32PeripheralUUID)
        XCTAssertNil(output.savedPeripheralIdentifier)
    }

    @MainActor func testOutputFramesUseDefaultVolumeAndRespectMute() throws {
        let suite = "device-frame-preferences-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let output = ESP32Output(defaults: defaults)
        defaults.set("보리", forKey: DefaultsKey.buddyName)
        defaults.set(3, forKey: DefaultsKey.soundVolume)
        defaults.set(true, forKey: DefaultsKey.soundsEnabled)
        func frame(_ state: BuddyState) throws -> [String: Any] {
            let data = try XCTUnwrap(output.frameData(from: state))
            XCTAssertEqual(data.last, 10)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        var state = BuddyState.initial
        state.creature.state = .working
        var object = try frame(state)
        XCTAssertEqual((object["snap"] as? [String: Any])?["name"] as? String, "보리")
        XCTAssertEqual(object["mute"] as? Int, SoundSettings.defaultVolume)
        defaults.set("Mochi", forKey: DefaultsKey.buddyName)
        defaults.set(false, forKey: DefaultsKey.soundsEnabled)
        state.creature.state = .done; state.creature.cheer = .cheer
        object = try frame(state)
        XCTAssertEqual((object["snap"] as? [String: Any])?["name"] as? String, "Mochi")
        XCTAssertEqual(object["mute"] as? Int, 0)
        XCTAssertEqual(object["cheer"] as? String, "cheer")
    }
}
