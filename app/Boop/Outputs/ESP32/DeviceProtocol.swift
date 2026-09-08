import Foundation

// Device → host contract: plan/WIRE-V2.md. Decode strictly before routing.
enum DevicePosture: String, Codable, Sendable { case desk, perch, travel }
enum DeviceMotion: String, Codable, Sendable { case shake, flip, pickup }
struct DeviceBattery: Codable, Sendable, Equatable {
    var pct: Int
    var charging: Bool
}
enum DeviceCommand: Sendable {
    case decision(id: String, decision: ApprovalDecision)
    case collect
    case boop(hold: Bool)
    case posture(DevicePosture)
    case motion(DeviceMotion)
    case battery(DeviceBattery)
    case focus(Bool)
    case ack(String)
    case status(board: String, contract: Int)
}

func parseDeviceLine(_ line: String) -> DeviceCommand? {
    struct Input: Decodable {
        var cmd: String?, id: String?, d: String?, decision: String?, ack: String?
        var hold: Bool?, p: DevicePosture?, m: DeviceMotion?, pct: Int?, charging: Bool?, on: Bool?
        var board: String?, contract: Int?
    }
    guard let data = line.data(using: .utf8), let i = try? JSONDecoder().decode(Input.self, from: data) else { return nil }
    if let ack = i.ack { return .ack(ack) }
    switch i.cmd {
    case "decision", "permission":
        guard let id = i.id, !id.isEmpty,
              let d = i.cmd == "decision" ? i.d : i.decision,
              d == "allow" || d == "deny" else { return nil }
        return .decision(id: id, decision: d == "allow" ? .allow : .deny)
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
