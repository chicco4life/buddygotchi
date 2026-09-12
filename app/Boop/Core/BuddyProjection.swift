import Foundation

// Pure display projection shared by Mac and device outputs. Lifecycle mutations
// stay in BuddyReducer; transport-specific byte and row caps stay in Heartbeat.
// MARK: - Aggregation

func aggregateBuddy(_ state: InternalState, now: Double) -> BuddyState {
    var buddy = state.buddy
    let allSessions = state.sessions.sorted { $0.key < $1.key }

    let waiting = allSessions.filter { $0.value.state == .needsConfirmation }
    let working = allSessions.filter { ($0.value.state == .working || $0.value.state == .thinking) && $0.value.uhoh == nil }
    let errored = allSessions.filter { $0.value.state != .needsConfirmation && ($0.value.state == .errored || $0.value.uhoh == .error) }

    buddy.sessions = SessionCounts(
        total: allSessions.count,
        running: working.count + waiting.count,
        waiting: waiting.count
    )

    let highestPrompt = waiting.min(by: { ($0.value.prompt?.arrivedAt ?? .infinity) < ($1.value.prompt?.arrivedAt ?? .infinity) })?.value.prompt
    buddy.prompt = highestPrompt

    // Build per-session breakdown for the popover. Order: needsConfirmation
    // (oldest prompt first) → errored (oldest workStartedAt) → working (oldest
    // workStartedAt) → idle (most recent first). The Mac receives every row;
    // only the device encoder limits its independent preview.
    let waitingOrdered = waiting
        .sorted { ($0.value.prompt?.arrivedAt ?? .infinity) < ($1.value.prompt?.arrivedAt ?? .infinity) }
    let erroredOrdered = errored
        .sorted { ($0.value.failedWorkStartedAt ?? $0.value.workStartedAt ?? .infinity) < ($1.value.failedWorkStartedAt ?? $1.value.workStartedAt ?? .infinity) }
    let workingOrdered = working
        .sorted { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) }
    let idleOrdered = allSessions
        .filter { $0.value.state == .idle && $0.value.uhoh == nil }
        .sorted { $0.value.lastActivityAt > $1.value.lastActivityAt }
    let combined = waitingOrdered + erroredOrdered + workingOrdered + idleOrdered
    var activeSnapshots: [SessionSnapshot] = []
    activeSnapshots.reserveCapacity(combined.count)
    for (id, sess) in combined {
        let tier = effortTier(elapsedMs: sess.workStartedAt.map { now - $0 } ?? 0)
        activeSnapshots.append(SessionSnapshot(
            cheer: sess.lastDone.flatMap { $0.until > now ? $0.size : nil },
            effort: tier.creatureEffort,
            id: id,
            source: sess.source,
            state: sess.uhoh == nil || sess.state == .needsConfirmation ? sess.state : .errored,
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            currentTool: sess.currentTool
        ))
    }
    buddy.activeSessions = activeSnapshots
    buddy.deviceThreads = allSessions.map { id, sess in
        DeviceThread(id: id, source: sess.source,
            status: sess.state == .needsConfirmation ? 2 : sess.uhoh != nil || sess.state == .errored ? 3 :
                (sess.state == .working || sess.state == .thinking) ? 1 : 0,
            title: deviceSessionTitle(id: id, session: sess))
    } // Stable session IDs keep table rows in place when their status changes.
    buddy.agentCounts = ["codex", "claude-code", "cursor", "other"].compactMap { source in
        let sessions = allSessions.map(\.value).filter {
            let group = ["codex", "claude-code", "cursor"].contains($0.source) ? $0.source : "other"
            return group == source
        }
        guard !sessions.isEmpty else { return nil }
        return AgentCounts(source: source,
            working: sessions.filter { ($0.state == .working || $0.state == .thinking) && $0.uhoh == nil }.count,
            idle: sessions.filter { $0.state == .idle && $0.uhoh == nil }.count)
    }

    // Project the oldest errored session for the popover Error card. Carries the
    // session id so dismissError(sessionId:) can target a specific one.
    let firstErroredSession = erroredOrdered.first
    buddy.firstErrored = firstErroredSession.map { id, sess in
        return ErroredSession(
            id: id,
            source: sess.source,
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            tool: sess.currentTool,
            hint: sess.currentHint,
            workStartedAt: sess.workStartedAt
        )
    }

    // The review surface clears as soon as a new prompt arrives (live state takes
    // visual primacy) or work resumes (the user reset the loop). It survives the
    // 4-second celebrate window into idle so the user can see what finished.
    if !waiting.isEmpty || !working.isEmpty {
        buddy.lastCompleted = nil
    }

    // Default — gets overwritten below in the busy branch when present.
    buddy.currentActivityKind = nil
    buddy.effortTier = nil

    let hasConnected = !allSessions.isEmpty
    buddy.desktop = DesktopLink(
        status: hasConnected ? .connected : .disconnected,
        lastHeartbeatAt: allSessions.lazy.map(\.value.lastActivityAt).max()
    )

    var creature = buddy.creature
    creature.effort = nil
    creature.cheer = nil
    creature.uhoh = nil
    creature.card = nil
    creature.overlay = nil
    creature.greetLevel = nil
    creature.nudgeRung = 0
    creature.dots = min(buddy.activeSessions.count, 5)
    creature.dotAlert = buddy.activeSessions.prefix(5).firstIndex { $0.state == .errored }
    if let prompt = highestPrompt {
        creature.state = .needsYou
        let stakes: Stakes = .checkIt // Legacy wire field; no safety classification.
        creature.card = CreatureCard(id: prompt.id, tool: prompt.tool, gloss: prompt.gloss ?? prompt.hint,
                                     stakes: stakes, index: 0, count: waiting.count, isApproval: false)
        creature.nudgeRung = state.nudges[prompt.id]?.rung ?? 0
        buddy.msg = shortMsg(tool: prompt.tool, hint: prompt.hint, source: prompt.source ?? "")
    } else if !errored.isEmpty {
        creature.state = .uhoh
        let primary = firstErroredSession?.value
        creature.uhoh = primary?.uhoh ?? .error
        let label = "Error"
        buddy.msg = primary?.currentTool.flatMap { $0.isEmpty ? nil : "\(label): \($0)" } ?? label
    } else if let moment = buddy.moment, moment.kind == .completed, now < moment.until {
        creature.state = .done
        creature.cheer = moment.tier == .full ? .dance : nil
        buddy.msg = moment.text
    } else if let until = buddy.celebrateUntil, now < until {
        creature.state = .done
        creature.cheer = state.doneSize ?? .hop
        buddy.msg = buddy.lastCompleted?.tool.map { "Done: \($0)" } ?? ""
    } else if let primary = workingOrdered.first?.value {
        creature.state = .working
        let tier = effortTier(elapsedMs: primary.workStartedAt.map { now - $0 } ?? 0)
        buddy.effortTier = tier
        creature.effort = tier.creatureEffort
        buddy.currentActivityKind = primary.currentActivityKind
        buddy.msg = primary.currentTool.map { shortMsg(tool: $0, hint: primary.currentHint ?? "", source: primary.source) } ?? ""
    } else {
        creature.state = hasConnected ? .idle : .asleep
        buddy.msg = buddy.lastCompleted?.tool.map { "Done: \($0)" } ?? ""
    }
    // Sleep wins over affection, like urgency does: a booped sleeper gets the
    // device's one-eye peek, not heart-eyes, and the desktop mirrors that.
    if creature.state == .idle || creature.state == .working || creature.state == .done {
        if let until = buddy.affectionUntil, now < until {
            creature.overlay = .boop
        } else if let until = buddy.greetUntil, now < until {
            creature.overlay = .greet
            creature.greetLevel = buddy.greetLevel == 2 ? 3 : 1
        }
    }
    buddy.creature = creature

    return buddy
}

/// Effort and celebrations share the same elapsed-duration thresholds.
func effortTier(elapsedMs: Double) -> EffortTier {
    if elapsedMs >= PetTuning.effortGrindingMinMs { return .grinding }
    if elapsedMs >= PetTuning.effortHardMinMs { return .hard }
    return .light
}
