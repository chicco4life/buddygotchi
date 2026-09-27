import BoopKit
import Foundation
import HookWire

/// Replays recorded hook payloads through the same field picking as
/// `boop-hook`, the adapter and a fresh core, on a virtual clock. Used by
/// `boopdev replay` and by tests.
public struct Replay {
    /// A payload, a `{"wait_ms": N}` line that waits, or an
    /// `{"advance_ms": N}` line that jumps a live app's clock; on the virtual
    /// clock both are just time passing. Lines with `expect` or `expect_not`
    /// are `boopctl e2e` checkpoints, skipped.
    public enum Step: Equatable {
        case payload(Data)
        case wait(Int64)
        case advance(Int64)
    }

    /// 2026-10-14 14:00 UTC, so output is repeatable.
    public static let defaultStart: Int64 = 1_791_986_400_000

    public var agent: String
    /// Virtual time between payloads.
    public var gapMs: Int64 = 1000
    public var start: Int64 = Replay.defaultStart
    public var time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    /// Start with today's rituals still to come.
    public var newDay = false

    public init(agent: String) {
        self.agent = agent
    }

    /// `.jsonl` gives one step per line; `.json` is a single payload.
    public static func steps(fromFile path: String) throws -> [Step] {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        if path.hasSuffix(".json") { return [.payload(Data(text.utf8))] }
        return text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               object["hook_event_name"] == nil {
                if let wait = object["wait_ms"] as? NSNumber { return .wait(wait.int64Value) }
                if let jump = object["advance_ms"] as? NSNumber { return .advance(jump.int64Value) }
                // Checkpoints for the pipeline check (`boopctl e2e`).
                if object["expect"] != nil || object["expect_not"] != nil { return nil }
            }
            return .payload(Data(line.utf8))
        }
    }

    /// Runs the steps and returns one line per event and effect, each
    /// effect prefixed with its virtual time.
    public func run(_ steps: [Step], statesOnly: Bool = false) -> [String] {
        var now = start
        let today = time.day(now)
        let core = Core(config: .init(name: "Pip", time: time), lastActiveDay: newDay ? nil : today)
        var out: [String] = []

        func emit(_ effects: [CoreEffect]) {
            for effect in effects {
                if statesOnly, case .state = effect {} else if statesOnly { continue }
                out.append("+" + String(format: "%.1f", Double(now - start) / 1000) + "s " + effect.summary)
            }
        }
        func advance(_ ms: Int64) {
            let end = now + ms
            while now < end {
                now = min(end, now + 1000)
                emit(core.tick(at: now))
            }
        }

        if !newDay { core.tick(at: now) }
        for step in steps {
            switch step {
            case .wait(let ms), .advance(let ms):
                advance(ms)
            case .payload(let data):
                guard let line = HookLine.extract(agent: agent, payload: data, ts: now) else {
                    if !statesOnly { out.append("# skipped: not a hook payload") }
                    continue
                }
                guard let event = Adapter.event(from: line) else {
                    if !statesOnly { out.append("# ignored hook \(line.hook)") }
                    continue
                }
                if !statesOnly { out.append("event " + event.jsonLine) }
                emit(core.handle(event))
                advance(gapMs)
            }
        }
        return out
    }
}
