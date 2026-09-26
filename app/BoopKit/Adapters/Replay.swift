import Foundation
import HookWire

/// Replays recorded hook payloads through the same field picking as
/// `boop-hook`, the adapter and a fresh core, on a virtual clock. Used by
/// `boopdev replay` and by tests.
public struct Replay {
    /// A payload, or a `{"wait_ms": N}` line that moves the clock. Lines
    /// with `expect` or `expect_not` are `boopctl e2e` checkpoints, skipped.
    public enum Step: Equatable {
        case payload(Data)
        case wait(Int64)
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
                // `advance_ms` jumps a live app's clock; here it's just time.
                if let wait = (object["wait_ms"] ?? object["advance_ms"]) as? NSNumber { return .wait(wait.int64Value) }
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
        var projects: [String: String] = [:]

        func emit(_ effects: [CoreEffect]) {
            for effect in effects {
                if statesOnly, case .state = effect {} else if statesOnly { continue }
                out.append("+" + String(format: "%.1f", Double(now - start) / 1000) + "s " + Replay.describe(effect))
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
            case .wait(let ms):
                advance(ms)
            case .payload(let data):
                guard let line = HookLine.extract(agent: agent, payload: data, ts: now) else {
                    if !statesOnly { out.append("# skipped: not a hook payload") }
                    continue
                }
                let key = line.agent + "/" + line.session
                guard let event = Adapter.event(from: line, knownProject: projects[key]) else {
                    if !statesOnly { out.append("# ignored hook \(line.hook)") }
                    continue
                }
                projects[key] = event.project
                if !statesOnly { out.append("event " + event.jsonLine) }
                emit(core.handle(event))
                advance(gapMs)
            }
        }
        return out
    }

    public static func describe(_ effect: CoreEffect) -> String {
        switch effect {
        case .state(let s): "state " + s.jsonLine
        case .moment(let anim): "moment \(anim)"
        case .mumble(let feeling, let word): "mumble \(feeling)" + (word.map { " \($0)" } ?? "")
        case .input(let i): "input " + i.line + (i.words.map { " \"\($0)\"" } ?? "")
        case .aside(let line): "aside " + line
        case .happened(let line): "happened \(line)"
        case .newDay(let date, let firstSeen): "new-day \(date) first seen \(firstSeen)"
        case .listen(let on): "listen \(on)"
        }
    }
}
