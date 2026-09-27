import Foundation

extension Eval {
    /// What the real brains did across an eval run's passes, for `boopdev
    /// eval --real` (VERIFICATION.md L5): refusals (a guardrail declining)
    /// counted apart, Stage 1's answers off the menu, the writer's slots,
    /// the calls actions dropped, and each input kind's latency against its
    /// deadline. It holds when Stage 1 answered every pass it didn't refuse,
    /// actions dropped under 5% of the calls handed to them, and every
    /// kind's p95 is under its deadline.
    public struct Summary: Sendable {
        public var lines: [String] = []
        public var holds: Bool

        /// The share of the calls handed to actions they may drop.
        public static let maxDropped = 0.05

        /// `passes` are the brains' own (`Result.brainPasses`): a step that
        /// scripts a stage tests the harness, not the brains.
        public init(_ passes: [Harness.Record]) {
            func percentile(_ values: [Int], _ p: Double) -> Int {
                let sorted = values.sorted()
                return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)]
            }
            lines.append("--- the real brains, over \(passes.count) passes")
            let refusals = passes.filter(\.refused)
            lines.append("refused: \(refusals.count)")
            for p in refusals { lines.append("  \(p.input.kind.rawValue): \(p.dropped ?? p.writeFailed ?? "")") }
            let unanswered = passes.filter { !$0.answered && !$0.refused }
            let answered = passes.count - unanswered.count - refusals.filter { !$0.answered }.count
            lines.append("stage 1 answered on the menu: \(answered)/\(passes.count)")
            for p in unanswered { lines.append("  dropped (\(p.input.kind.rawValue)): \(p.dropped ?? "")") }
            let asked = passes.filter { !$0.slots.isEmpty }
            let slots = asked.flatMap { p in p.slots.map { p.wrote[$0] ?? "" } }
            let writerFailed = asked.filter { $0.writeFailed != nil }.count
            lines.append("writer: \(asked.count) passes, \(slots.filter { !$0.isEmpty }.count)/\(slots.count) slots filled, "
                         + "\(writerFailed) failed")
            let ran = passes.flatMap(\.ran)
            let handed = ran.filter { $0.outcome != .dropped("nothing was written") }
            let dropped = handed.filter { !$0.outcome.isDone }
            lines.append("calls: \(handed.count) to actions, \(dropped.count) dropped by them, "
                         + "\(ran.count - handed.count) with nothing written")
            for d in dropped {
                if case .dropped(let why) = d.outcome { lines.append("  \(d.call.plain): \(why)") }
            }
            var inTime = true
            for kind in Input.Kind.allCases {
                let ps = passes.filter { $0.input.kind == kind }
                guard !ps.isEmpty else { continue }
                let p95 = percentile(ps.map(\.latencyMs), 0.95)
                if p95 >= kind.deadlineMs { inTime = false }
                let writes = ps.filter { !$0.slots.isEmpty }.map(\.writeMs)
                lines.append("latency \(kind.rawValue): n \(ps.count), classify p50 \(percentile(ps.map(\.classifyMs), 0.5)) ms, "
                             + "write p50 \(percentile(writes, 0.5)) ms (n \(writes.count)), "
                             + "p95 \(p95) ms (deadline \(kind.deadlineMs) ms)")
            }
            holds = unanswered.isEmpty && inTime
                && (handed.isEmpty || Double(dropped.count) / Double(handed.count) < Summary.maxDropped)
            lines.append(holds ? "the report held: answered, in time, few drops" : "the report did NOT hold (above)")
        }
    }
}
