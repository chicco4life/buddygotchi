import Foundation

struct Extraction: Sendable { var events: [BuddyEvent] = []; var facts: [Fact] = [] }
actor Extractor {
    private(set) var windows: [String: SessionWindow] = [:]
    private var degraded: Set<String> = []
    func reset() { windows.removeAll() }
    func drop(sessionId: String) { windows.removeValue(forKey: sessionId) }
    func ingest(_ p: RawHookPayload, localHour: Int? = nil) -> Extraction {
        var result = Extraction(events: LifecycleReader.read(p))
        if p.kind == .sessionEnd {
            if let w = windows.removeValue(forKey: p.sessionId) { result.facts.append(Fact(kind: .sessionSummary, sessionId: p.sessionId, project: w.project, at: p.timestamp, payload: ["attempts": String(w.goals.values.reduce(0) { $0 + $1.attempts })])) }
            return result
        }
        let isNewWindow = windows[p.sessionId] == nil
        var w = windows[p.sessionId] ?? SessionWindow(project: ThemeReader.projectIdentity(cwd: p.cwd), startedAt: p.timestamp)
        func fact(_ kind: Fact.Kind, _ payload: [String: String]) -> Fact { Fact(kind: kind, sessionId: p.sessionId, project: w.project, at: p.timestamp, payload: payload) }
        let missing = (p.kind == .toolCall && (p.toolInput == nil || p.toolName.isEmpty)) || (p.kind == .toolResult && p.toolName.isEmpty)
        if missing && degraded.insert(p.source).inserted { result.events.append(.adapterDegraded(at: p.timestamp, source: p.source)) }
        if degraded.contains(p.source) { windows[p.sessionId] = w; return result }
        switch p.kind {
        case .sessionStart:
            result.facts.append(fact(.theme, ["project": w.project]))
        case .turnStart:
            if let prompt = p.promptText { result.facts.append(fact(.tone, ["tone": ThemeReader.tone(prompt), "topics": ThemeReader.topics(prompt).joined(separator: ",")])) }
            w.append(.init(kind: .turnStart, at: p.timestamp, text: ""))
            if let localHour { result.events.append(.localTurnHour(at: p.timestamp, sessionId: p.sessionId, hour: localHour)) }
        case .toolCall:
            let input = p.toolInput ?? ""
            w.append(.init(kind: .toolCall, at: p.timestamp, text: input))
            var signature = ""
            var runnerName = ""
            if let command = GoalsReader.command(input), let runner = GoalsReader.runner(command) {
                signature = GoalsReader.signature(command, project: w.project)
                var tally = w.goals[signature] ?? GoalTally(firstAt: p.timestamp)
                if tally.lastOutcome == .pass { tally.firstAt = p.timestamp }
                tally.attempts += 1; tally.attemptsWithoutPass += 1
                w.goals[signature] = tally
                runnerName = runner.runner.name
            }
            w.pending.append((signature, runnerName, p.toolName, p.callId))
            if w.pending.count > SessionWindow.entryCap { w.pending.removeFirst() }
            result.events.append(.toolCalled(at: p.timestamp, sessionId: p.sessionId, source: p.source, tool: p.toolName, hint: signature))
            if let path = ThemeReader.path(input) {
                let topic = String((path as NSString).pathExtension.prefix(16))
                if !topic.isEmpty && !w.topics.contains(topic) && w.topics.count < 3 { w.topics.append(topic) }
                result.facts.append(fact(.theme, ["topics": w.topics.joined(separator: ",")]))
            }
            if let path = ThemeReader.path(input), ["edit", "write", "apply_patch"].contains(p.toolName.lowercased()) {
                w.edits[path, default: 0] += 1
                result.events.append(.fileEdited(at: p.timestamp, sessionId: p.sessionId, path: path, count: w.edits[path]!))
            }
        case .toolResult:
            if p.source == "cursor", p.toolName == "Edit", let input = p.toolInput, let path = ThemeReader.path(input) {
                w.edits[path, default: 0] += 1
                result.events.append(.fileEdited(at: p.timestamp, sessionId: p.sessionId, path: path, count: w.edits[path]!))
            }
            w.append(.init(kind: .toolResult, at: p.timestamp, text: (p.outputHead ?? "") + (p.outputTail ?? "")))
            var outcome: GoalOutcome = p.exitStatus.map { $0 == 0 ? .pass : .fail } ?? .unknown
            if let index = w.pending.firstIndex(where: { p.callId != nil ? $0.callId == p.callId : $0.tool == p.toolName }) {
                let pending = w.pending.remove(at: index)
                if let runner = GoalsReader.runners.first(where: { $0.runner.name == pending.runner }), var tally = w.goals[pending.signature] {
                    outcome = GoalsReader.outcome(p, runner: runner)
                    if outcome == .fail { tally.failures += 1; tally.consecutiveFailures += 1; if tally.firstFailureAt == nil { tally.firstFailureAt = p.timestamp } }
                    result.events.append(.goalRead(at: p.timestamp, sessionId: p.sessionId, goal: pending.signature, outcome: outcome, tally: tally))
                    result.facts.append(fact(.goalOutcome, ["goal": pending.signature, "runner": pending.runner, "outcome": outcome.rawValue, "attempts": String(tally.attempts), "elapsedMs": String(max(0, p.timestamp - tally.firstAt))]))
                    if outcome == .pass { tally.attemptsWithoutPass = 0; tally.consecutiveFailures = 0; tally.failures = 0; tally.firstFailureAt = nil }
                    if outcome == .unknown { tally.consecutiveFailures = 0; tally.firstFailureAt = nil }
                    tally.lastOutcome = outcome; w.goals[pending.signature] = tally
                }
            }
            if outcome == .fail { w.errors += 1 }
            // Result first clears a stuck state on a proven pass; goalRead then supplies story evidence.
            result.events.insert(.toolResulted(at: p.timestamp, sessionId: p.sessionId, source: p.source, tool: p.toolName, ok: outcome == .unknown ? nil : outcome == .pass, durationMs: nil), at: 0)
        case .turnEnd:
            if !p.closingOnly { w.append(.init(kind: .turnEnd, at: p.timestamp, text: "")) }
            if let message = p.closingMessage { w.append(.init(kind: .closingMessage, at: p.timestamp, text: ClosingLineReader.read(message))) }
        case .needsYou:
            let (stakes, gloss) = StakesReader.read(tool: p.toolName, input: p.toolInput ?? "")
            result.events.append(.requestArrived(at: p.timestamp, sessionId: p.sessionId, requestId: "\(p.sessionId)_\(Int(p.timestamp))", tool: p.toolName, hint: gloss, sessionLabel: w.project))
            result.events.append(.requestDescribed(at: p.timestamp, sessionId: p.sessionId, stakes: stakes, gloss: gloss))
        case .sessionEnd: break
        }
        if let error = p.errorClass { result.facts.append(fact(.errorClass, ["class": ["rate_limit", "tool_error", "auth", "timeout"].contains(error) ? error : "unknown"])) }
        if p.kind == .toolCall || p.kind == .toolResult { result.events.append(.effortObserved(at: p.timestamp, sessionId: p.sessionId, level: EffortReader.read(w, at: p.timestamp))) }
        if isNewWindow && !p.closingOnly { result.events.append(.projectObserved(at: p.timestamp, sessionId: p.sessionId, project: w.project)) }
        windows[p.sessionId] = w
        return result
    }
}
