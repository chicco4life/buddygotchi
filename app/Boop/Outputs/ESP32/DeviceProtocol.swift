import LeaderboardWire
import Foundation
import CoreFoundation

// Device → host contract: plan/WIRE-V2.md. Decode strictly before routing.
enum DevicePosture: String, Codable, Sendable { case desk, perch, travel }
enum DeviceMotion: String, Codable, Sendable { case shake, flip, pickup }
struct DeviceBattery: Codable, Sendable, Equatable {
    var pct: Int
    var charging: Bool
}
enum DeviceCommand: Sendable {
    case decision(id: String, decision: ApprovalDecision)
    case quick
    case collect
    case boop(hold: Bool)
    case posture(DevicePosture)
    case motion(DeviceMotion)
    case battery(DeviceBattery)
    case focus(Bool)
    case identity(DeviceIdentity)
    case signature(LedgerSignature)
    case ack(String)
    case status(board: String, contract: Int)
}

/// Pre-v2 firmware shapes, rewritten to v2 before parsing. Remove with the
/// first release after every shipped device runs contract 2.
func normalizeLegacyDeviceLine(_ line: String) -> String {
    guard let data = line.data(using: .utf8),
          var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cmd = json["cmd"] as? String else { return line }
    switch cmd {
    case "permission":
        json["cmd"] = "decision"; json["d"] = json.removeValue(forKey: "decision")
    case "boop" where json["hold"] == nil:
        json["hold"] = false
    default: return line
    }
    guard let out = try? JSONSerialization.data(withJSONObject: json), let text = String(data: out, encoding: .utf8) else { return line }
    return text
}

func parseDeviceLine(_ rawLine: String) -> DeviceCommand? {
    let line = normalizeLegacyDeviceLine(rawLine)
    struct Input: Decodable {
        var cmd: String?, id: String?, d: String?, ack: String?
        var hold: Bool?, p: DevicePosture?, m: DeviceMotion?, pct: Int?, charging: Bool?, on: Bool?
        var board: String?, contract: Int?
    }
    guard let data = line.data(using: .utf8), let i = try? JSONDecoder().decode(Input.self, from: data) else { return nil }
    if let ack = i.ack {
        struct Ack: Decodable { var ok: Bool }
        switch ack {
        case "unit":
            guard (try? JSONDecoder().decode(Ack.self, from: data).ok) == true,
                  let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data), identity.valid else { return nil }
            return .identity(identity)
        case "sign":
            guard (try? JSONDecoder().decode(Ack.self, from: data).ok) == true,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  integerValue(object["xp"]) != nil,
                  let signature = try? JSONDecoder().decode(LedgerSignature.self, from: data) else { return nil }
            return .signature(signature)
        default: return .ack(ack)
        }
    }
    switch i.cmd {
    case "decision":
        guard let id = i.id, !id.isEmpty, let d = i.d, d == "allow" || d == "deny" else { return nil }
        return .decision(id: id, decision: d == "allow" ? .allow : .deny)
    case "quick": return .quick
    case "collect": return .collect
    case "boop": return .boop(hold: i.hold ?? false)
    case "posture": return i.p.map(DeviceCommand.posture)
    case "motion": return i.m.map(DeviceCommand.motion)
    case "battery":
        guard let pct = i.pct, (0...100).contains(pct), let charging = i.charging else { return nil }
        return .battery(.init(pct: pct, charging: charging))
    case "focus": return i.on.map(DeviceCommand.focus)
    case "status":
        guard let board = i.board, let contract = i.contract, contract == 2 else { return nil }
        return .status(board: board, contract: contract)
    default: return nil
    }
}

private func integerValue(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          !["d", "f"].contains(String(cString: number.objCType)) else { return nil }
    return Int(number.stringValue)
}
