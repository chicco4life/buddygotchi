import Foundation

// MARK: - Internal State

struct InternalState: Sendable, Equatable {
    var buddy: BuddyState
    var sessions: [String: Session]
    var staleMs: Double
    var celebrateDurationMs: Double
    var workStallTimeoutMs: Double
    var approvalTimeoutMs: Double
    /// Sessions whose agent host process has a live exit watcher. Fed by
    /// `.processWatchChanged`; exempt from the stale-activity reap because the
    /// watcher reports death definitively — silence is not evidence.
    var watchedSessionIds: Set<String> = []
    /// The pet's persisted inner life (System P). Seeded via `.memoryLoaded`,
    /// mutated only here, written back by the engine when it changes.
    var memory: PetMemory = .empty

    var cheerThresholds: CheerThresholds = .defaults
    var nudgeTiming: NudgeTiming = .defaults
    var nudges: [String: CardNudge] = [:]
    var snoozedTools: [String: Set<String>] = [:]
    var bubbleUntil: Double?
    /// Size of the cheer currently playing; `celebrateUntil` is its timer.
    var doneSize: CheerSize?

    var version: Int { buddy.version }

    static func initial(staleMs: Double, celebrateDurationMs: Double, workStallTimeoutMs: Double = 300_000, approvalTimeoutMs: Double = 290_000) -> InternalState {
        InternalState(buddy: .initial, sessions: [:], staleMs: staleMs, celebrateDurationMs: celebrateDurationMs, workStallTimeoutMs: workStallTimeoutMs, approvalTimeoutMs: approvalTimeoutMs)
    }
}

// MARK: - Reducer

func reduce(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    var next = reduceInner(state, event)
    updateCreatureTimers(&next, event: event)
    // Recompute even on a quiet tick so effort and timed projections advance.
    // `updatedAt` is left alone until we know something changed: a timestamp
    // alone is not a state change worth notifying outputs about.
    next.buddy = aggregate(next, now: event.at)
    guard next != state else { return state }
    next.buddy.version = state.buddy.version + 1
    next.buddy.updatedAt = event.at
    return next
}

private func reduceInner(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    switch event {
    case .devicePostureChanged(_, let posture):
        var s = state
        s.buddy.devicePosture = posture
        return s
    case .deviceBatteryChanged(_, let battery):
        var s = state
        s.buddy.deviceBattery = battery
        return s
    case .turnStarted(let at, let id, let source):
        return handleTurnStarted(state, at: at, sessionId: id, source: source)
    case .toolCalled(let at, let id, let source, let tool, let hint):
        return handleToolCalled(state, at: at, sessionId: id, source: source, tool: tool, hint: hint)
    case .toolResulted(let at, let id, let source, let tool, let ok, _):
        return handleToolResulted(state, at: at, sessionId: id, source: source, tool: tool, ok: ok)
    case .turnEnded(let at, let id, let source, let outcome):
        return handleTurnEnded(state, at: at, sessionId: id, source: source, outcome: outcome)
    case .focusToggled(_, let on):
        var s = state
        s.buddy.creature.focus = on
        return s
    case .collectArrived(let at):
        var s = state
        collectGift(&s, at: at)
        return s
    case .nudgeDismissed(let at):
        return dismissNudge(state, at: at)
    case .sessionStarted(let at, let sessionId, let source, let cwd):
        return handleSessionStarted(state, at: at, sessionId: sessionId, source: source, cwd: cwd)
    case .sessionEnded(_, let sessionId):
        return handleSessionEnded(state, sessionId: sessionId)
    case .requestArrived(let at, let sessionId, let requestId, let tool, let hint, let sessionLabel):
        return handleRequestArrived(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)
    case .requestCleared(let at, let sessionId):
        return handleRequestCleared(state, at: at, sessionId: sessionId)
    case .activitySignal(let at, let sessionId, let source, let signal, let tool, let hint):
        // Compatibility input: the same turn/tool handlers, with the legacy
        // signal's tool/hint stamped through the one shared helper.
        switch signal {
        case .startWorking:
            return handleTurnStarted(state, at: at, sessionId: sessionId, source: source, tool: tool, hint: hint)
        case .keepWorking:
            return handleToolCalled(state, at: at, sessionId: sessionId, source: source, tool: tool ?? "", hint: hint ?? "")
        case .stopWorking, .celebrate:
            return handleTurnEnded(state, at: at, sessionId: sessionId, source: source, outcome: .completed, tool: tool, hint: hint)
        case .error:
            return handleTurnEnded(state, at: at, sessionId: sessionId, source: source, outcome: .failed(errorClass: nil), tool: tool, hint: hint)
        }
    case .staleTick(let at):
        return handleStaleTick(state, now: at)
    case .approvalArrived(let at, let sessionId, let requestId, let tool, let hint, let sessionLabel, let source):
        return handleApprovalArrived(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: source)
    case .approvalResolved(let at, let sessionId, let requestId, let decision):
        return handleApprovalResolved(state, at: at, sessionId: sessionId, requestId: requestId, decision: decision)
    case .approvalAbandoned(let at, let sessionId, let requestId):
        return handleApprovalAbandoned(state, at: at, sessionId: sessionId, requestId: requestId)
    case .processWatchChanged(_, let watchedSessionIds):
        var s = state
        s.watchedSessionIds = watchedSessionIds
        return s
    case .speciesChanged(_, let species):
        return handleSpeciesChanged(state, species: species)
    case .boopArrived(let at):
        return handleBoopArrived(state, at: at)
    case .reviewDismissed:
        return handleReviewDismissed(state)
    case .errorDismissed(let at, let sessionId):
        return handleErrorDismissed(state, at: at, sessionId: sessionId)
    case .memoryLoaded(_, let memory):
        var s = state
        s.memory = memory
        return s
    case .effortReported(_, let sessionId, let level):
        guard state.sessions[sessionId] != nil else { return state }
        var s = state
        s.sessions[sessionId]?.reportedEffort = level
        return s
    case .agentIntroduced(let at, let agentId, let color, let signatureEmote, let greeting):
        return handleAgentIntroduced(state, at: at, agentId: agentId, color: color, signatureEmote: signatureEmote, greeting: greeting)
    case .agentExpressed(let at, let agentId, let emotion, let intensity, let motion, let say, let delivery):
        return handleAgentExpressed(state, at: at, agentId: agentId, emotion: emotion, intensity: intensity, motion: motion, say: say, delivery: delivery)
    case .agentDrew(let at, let agentId, let rows, let caption):
        return handleAgentDrew(state, at: at, agentId: agentId, rows: rows, caption: caption)
    }
}

// MARK: - Event Handlers

private func handleSessionStarted(_ state: InternalState, at: Double, sessionId: String, source: String, cwd: String?) -> InternalState {
    var s = state
    let isNewSession = s.sessions[sessionId] == nil
    // Judge the hour against history BEFORE this arrival samples into it —
    // otherwise the session's own sample dilutes "have I ever worked now?".
    let atUnusualHour = s.memory.circadianReady(at: at) && s.memory.isUnusualHour(PetMemory.utcHour(ofMs: at))
    observePresence(&s, at: at)
    if isNewSession {
        s.sessions[sessionId] = Session(source: source, state: .idle, prompt: nil, cwd: cwd, lastActivityAt: at, workStartedAt: nil)
        s.memory.lifetimeSessions += 1
        // Surprised-then-cozy: a session at an hour this user never works.
        // Only on a genuinely new session, so per-event sessionStarted
        // re-sends don't retrigger it.
        if atUnusualHour {
            s.buddy.mood = .surprised
            s.buddy.moodUntil = at + PetTuning.surpriseMoodMs
        }
    } else {
        let existingCwd = s.sessions[sessionId]?.cwd
        s.sessions[sessionId]?.lastActivityAt = at
        s.sessions[sessionId]?.cwd = cwd ?? existingCwd
    }
    // Anticipation is for before you arrive; a live session ends it.
    if s.buddy.mood == .expectant {
        s.buddy.mood = nil
    }
    return s
}

private func handleSessionEnded(_ state: InternalState, sessionId: String) -> InternalState {
    var s = state
    s.sessions.removeValue(forKey: sessionId)
    return s
}

private func handleRequestArrived(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?) -> InternalState {
    setPrompt(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: nil, isApproval: false)
}

/// A blocking approval is owed an answer, so ordinary work activity must not
/// silently withdraw it.
///
/// The agent runs tools in parallel: a `Read` finishing sends PostToolUse for
/// the same session while a `Bash` PermissionRequest is still parked. That
/// used to wipe the prompt — the card vanished from popover and device
/// mid-glance and the blocked hook returned passthrough, so approval mode was
/// unreliable in any session doing more than one thing at a time. A passive
/// notification card carries no blocked caller and is still dismissed here.
private func hasBlockingApproval(_ session: Session?) -> Bool {
    session?.prompt?.isApproval == true
}

private func handleRequestCleared(_ state: InternalState, at: Double, sessionId: String) -> InternalState {
    guard let session = state.sessions[sessionId], session.state == .needsConfirmation else {
        return state
    }
    if hasBlockingApproval(session) {
        var s = state
        s.sessions[sessionId]?.lastActivityAt = at
        return s
    }
    var s = state
    s.sessions[sessionId]?.state = .working
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.lastActivityAt = at
    // Same gap as handleApprovalResolved: entering .working without a start
    // time is permanent, because keepWorking only stamps it on the way IN.
    if s.sessions[sessionId]?.workStartedAt == nil {
        s.sessions[sessionId]?.workStartedAt = at
    }
    s.sessions[sessionId]?.lastWorkSignalAt = at
    return s
}

/// "What is the agent doing" fields, stamped in one place so every path
/// (tool call, legacy signal) records the same set.
private func stampTool(_ s: inout InternalState, sessionId: String, tool: String?, hint: String?) {
    guard let tool, !tool.isEmpty else { return }
    s.sessions[sessionId]?.lastTool = tool
    s.sessions[sessionId]?.lastHint = hint
    s.sessions[sessionId]?.currentTool = tool
    s.sessions[sessionId]?.currentHint = hint
    s.sessions[sessionId]?.currentActivityKind = activityKind(tool: tool, hint: hint ?? "")
}

/// The one "session is alive and working again" rule: clears uh-oh, resets
/// the repeat counter, and (unless an approval blocks it) returns to working.
private func markAlive(_ s: inout InternalState, sessionId: String, at: Double) {
    s.sessions[sessionId]?.uhoh = nil
    s.sessions[sessionId]?.repeatedToolCount = 0
    s.sessions[sessionId]?.lastWorkSignalAt = at
    if s.sessions[sessionId]?.workStartedAt == nil { s.sessions[sessionId]?.workStartedAt = at }
    if !hasBlockingApproval(s.sessions[sessionId]) {
        s.sessions[sessionId]?.state = .working
        s.sessions[sessionId]?.prompt = nil
    }
}

private func handleTurnStarted(_ state: InternalState, at: Double, sessionId: String, source: String, tool: String? = nil, hint: String? = nil) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    stampTool(&s, sessionId: sessionId, tool: tool, hint: hint)
    markAlive(&s, sessionId: sessionId, at: at)
    return s
}

private func handleToolResulted(_ state: InternalState, at: Double, sessionId: String, source: String, tool: String, ok: Bool?) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    s.sessions[sessionId]?.lastWorkSignalAt = at
    if ok == true {
        markAlive(&s, sessionId: sessionId, at: at)
    } else if ok == false {
        s.sessions[sessionId]?.errorCount += 1
    }
    if !tool.isEmpty { s.sessions[sessionId]?.currentTool = tool }
    return s
}

private func handleToolCalled(_ state: InternalState, at: Double, sessionId: String, source: String, tool: String, hint: String) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    let previous = s.sessions[sessionId]!
    s.sessions[sessionId]?.repeatedToolCount = previous.lastTool == tool && previous.lastHint == hint ? previous.repeatedToolCount + 1 : 1
    s.sessions[sessionId]?.lastWorkSignalAt = at
    if previous.workStartedAt == nil { s.sessions[sessionId]?.workStartedAt = at }
    stampTool(&s, sessionId: sessionId, tool: tool, hint: hint)
    if !hasBlockingApproval(previous) {
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.state = previous.uhoh == nil ? .working : previous.state
    }
    if s.sessions[sessionId]!.repeatedToolCount >= 6 {
        enterUhoh(&s, sessionId: sessionId, kind: .stuck, at: at)
    }
    s.buddy.entries.insert(shortMsg(tool: tool, hint: hint, source: source), at: 0)
    if s.buddy.entries.count > 10 { s.buddy.entries.removeLast(s.buddy.entries.count - 10) }
    return s
}

private func handleTurnEnded(_ state: InternalState, at: Double, sessionId: String, source: String, outcome: TurnOutcome, tool: String? = nil, hint: String? = nil) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)
    stampTool(&s, sessionId: sessionId, tool: tool, hint: hint)
    let session = s.sessions[sessionId]!
    switch outcome {
    case .failed(let errorClass):
        s.sessions[sessionId]?.errorCount += 1
        enterUhoh(&s, sessionId: sessionId, kind: errorClass == "rate_limit" ? .hungry : .error, at: at)
    case .completed:
        s.sessions[sessionId]?.uhoh = nil
        guard !hasBlockingApproval(session) else { return s }
        s.sessions[sessionId]?.state = .idle
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.workStartedAt = nil
        s.sessions[sessionId]?.lastWorkSignalAt = nil
        s.sessions[sessionId]?.currentTool = nil
        s.sessions[sessionId]?.currentHint = nil
        s.sessions[sessionId]?.currentActivityKind = nil
        s.sessions[sessionId]?.repeatedToolCount = 0
        guard let start = session.workStartedAt else { return s }
        let duration = max(0, at - start)
        let size = s.cheerThresholds.size(errors: session.errorCount, span: duration, effort: effortTier(for: session, elapsedMs: duration))
        // A smaller nearby completion cannot truncate or restart the larger cheer.
        let folded = s.buddy.lastCompletionAt.map { at - $0 <= s.cheerThresholds.foldMs } ?? false
        if !folded || size.intensity > (s.doneSize?.intensity ?? 0) {
            s.doneSize = size
            s.buddy.celebrateUntil = at + s.cheerThresholds.duration(size)
        }
        // A pending orb always carries the newest story line.
        if s.buddy.creature.gift { s.buddy.creature.giftLine = giftLine(forHint: session.lastHint) }
        s.memory.lifetimeCelebrations += 1
        s.sessions[sessionId]?.errorCount = 0
        s.sessions[sessionId]?.reportedEffort = nil
        s.buddy.lastTaskDurationMs = duration
        s.buddy.lastCompletionAt = at
        s.buddy.lastCompleted = CompletedTask(
            id: "\(sessionId)_\(Int(at))", tool: session.lastTool, hint: session.lastHint,
            source: source, sessionLabel: session.cwd.flatMap { ($0 as NSString).lastPathComponent },
            durationMs: duration, completedAt: at,
            activityKind: session.currentActivityKind ?? .work)
    }
    return s
}

private func handleStaleTick(_ state: InternalState, now: Double) -> InternalState {
    var changed = false
    var s = state

    if let until = s.buddy.celebrateUntil, now >= until {
        s.buddy.creature.gift = true
        s.buddy.creature.giftLine = giftLine(forHint: s.buddy.lastCompleted?.hint)
        s.buddy.celebrateUntil = nil
        s.buddy.lastTaskDurationMs = nil
        changed = true
    }

    if let until = s.buddy.affectionUntil, now >= until {
        s.buddy.affectionUntil = nil
        changed = true
    }

    if let until = s.buddy.greetUntil, now >= until {
        s.buddy.greetUntil = nil
        s.buddy.greetLevel = nil
        changed = true
    }

    // Possession lease (S8): the agent's expression expires; the pet is
    // itself again.
    if let overlay = s.buddy.agentOverlay, now >= overlay.until {
        s.buddy.agentOverlay = nil
        changed = true
    }

    // The pet finishes admiring a fresh drawing and shelves it (the
    // keepsake persists in memory; only the held-up display ends).
    if let until = s.buddy.agentDrawingUntil, now >= until {
        s.buddy.agentDrawing = nil
        s.buddy.agentDrawingUntil = nil
        s.buddy.agentDrawingIsMemory = nil
        changed = true
    }

    if let until = s.buddy.moodUntil, now >= until {
        s.buddy.moodUntil = nil
        if s.buddy.mood == .surprised { s.buddy.mood = nil }
        changed = true
    }

    // Expectant: awake-with-anticipation around the user's usual start hour,
    // before any session shows up. Never overrides an active surprised window.
    if s.buddy.moodUntil == nil {
        let expectant = s.sessions.isEmpty
            && s.memory.circadianReady(at: now)
            && s.memory.isTypicalHour(PetMemory.utcHour(ofMs: now))
        let newMood: PetMood? = expectant ? .expectant : (s.buddy.mood == .expectant ? nil : s.buddy.mood)
        if newMood != s.buddy.mood {
            s.buddy.mood = newMood
            changed = true
        }
    }

    // Stall detection: a session in .working that hasn't bumped lastWorkSignalAt
    // for workStallTimeoutMs is presumed "thinking hard" — not an error. Real
    // errors only come from explicit .error signals (e.g. Claude Code StopFailure).
    // Run BEFORE the stale-session prune so a quiet session reports thinking
    // before being reaped.
    for (id, session) in s.sessions where session.state == .working {
        if let lastSignal = session.lastWorkSignalAt,
           now - lastSignal > s.workStallTimeoutMs,
           let started = session.workStartedAt,
           now - started > s.workStallTimeoutMs {
            enterUhoh(&s, sessionId: id, kind: .stuck, at: now)
            changed = true
        }
    }

    for (id, session) in s.sessions {
        guard let prompt = session.prompt, now - prompt.arrivedAt > s.approvalTimeoutMs else { continue }
        s.sessions[id]?.prompt = nil
        s.sessions[id]?.state = .idle
        s.sessions[id]?.lastActivityAt = now
        changed = true
    }

    // Supervised sessions (live process watcher) are exempt: the watcher
    // delivers sessionEnded the instant the agent host exits, so a quiet
    // 15-minute build shouldn't make the pet give up and sleep.
    let staleIds = s.sessions.filter {
        now - $0.value.lastActivityAt > s.staleMs && !s.watchedSessionIds.contains($0.key)
    }.map(\.key)
    for id in staleIds {
        s.sessions.removeValue(forKey: id)
        changed = true
    }

    guard changed else { return state }
    return s
}

private func handleApprovalArrived(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?) -> InternalState {
    setPrompt(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel, source: source, isApproval: true)
}

private func handleApprovalResolved(_ state: InternalState, at: Double, sessionId: String, requestId: String, decision: ApprovalDecision) -> InternalState {
    guard let session = state.sessions[sessionId],
          session.state == .needsConfirmation,
          session.prompt?.id == requestId else {
        return state
    }
    var s = state
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.state = decision == .allow ? .working : .idle
    s.sessions[sessionId]?.lastActivityAt = at
    if decision == .allow {
        // Entering .working here without a start time was permanent: the
        // keepWorking branch only stamps workStartedAt when the prior state
        // ISN'T .working, so it never filled it in later. That left the
        // session unable to ever look stalled (stall detection needs both
        // timestamps) and made its eventual completion durationless — no
        // celebrate sound, no elapsed time on the review card. It bites any
        // session Boop first meets at an approval.
        if s.sessions[sessionId]?.workStartedAt == nil {
            s.sessions[sessionId]?.workStartedAt = at
        }
        s.sessions[sessionId]?.lastWorkSignalAt = at
    }
    return s
}

/// The hook that was waiting on this approval is gone — its HTTP request was
/// cancelled (agent killed, curl timed out, or the agent's own hook timeout
/// fired and it fell back to its native prompt). The card must come down NOW:
/// leaving it up invites the user to "approve" something nobody can act on,
/// while the terminal is already showing the real prompt.
private func handleApprovalAbandoned(_ state: InternalState, at: Double, sessionId: String, requestId: String) -> InternalState {
    guard let session = state.sessions[sessionId],
          session.state == .needsConfirmation,
          session.prompt?.id == requestId else {
        // Already superseded, resolved, or expired — nothing to withdraw.
        return state
    }
    var s = state
    s.sessions[sessionId]?.prompt = nil
    s.sessions[sessionId]?.state = .idle
    s.sessions[sessionId]?.lastActivityAt = at
    return s
}

/// How long a device boop keeps the desktop pet in heart-eyes. Mirrors the
/// firmware's BOOP_REACT_MS; sustained petting re-sends boops (rate-limited to
/// ~1.5s) so the window keeps sliding for the whole stroke.
let boopAffectionMs: Double = 2500

private func handleBoopArrived(_ state: InternalState, at: Double) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    collectGift(&s, at: at)
    s.buddy.affectionUntil = at + boopAffectionMs
    return s
}

// MARK: - Personality Handlers

/// Every user-adjacent event passes through here: it stamps `lastSeenAt`,
/// triggers the return-greeting when a real absence just ended, and samples
/// the circadian histogram (at most one sample per ~30 min so activity volume
/// doesn't skew the shape). Absence is a ratchet — a gap earns warmth on
/// return, never a penalty.
private func observePresence(_ s: inout InternalState, at: Double) {
    if let last = s.memory.lastSeenAt, at - last >= PetTuning.greetGapMs {
        let big = at - last >= PetTuning.greetBigGapMs
        s.buddy.greetUntil = at + (big ? PetTuning.greetBigMs : PetTuning.greetShortMs)
        s.buddy.greetLevel = big ? 2 : 1
    }
    if s.memory.lastSampleAt.map({ at - $0 >= PetTuning.circadianSampleGapMs }) ?? true {
        let hour = PetMemory.utcHour(ofMs: at)
        s.memory.hourHistogram[hour] += 1
        s.memory.histogramSamples += 1
        if s.memory.firstSampleAt == nil { s.memory.firstSampleAt = at }
        s.memory.lastSampleAt = at
    }
    s.memory.lastSeenAt = at
}

private func handleAgentIntroduced(_ state: InternalState, at: Double, agentId: String, color: String?, signatureEmote: String?, greeting: String?) -> InternalState {
    var s = state
    let isReturning = s.memory.agents[agentId] != nil
    var identity = s.memory.agents[agentId] ?? AgentIdentity()
    if let color { identity.color = color }
    if let signatureEmote { identity.signatureEmote = signatureEmote }
    if let greeting { identity.greeting = greeting }
    identity.visits += 1
    identity.lastSeenAt = at
    s.memory.agents[agentId] = identity

    // "Remember this?" — a returning agent's old drawing comes back out.
    // At most once a day, only drawings old enough to be memories, never
    // while a prompt is pending (S1), and deterministic off the event
    // timestamp so the choice is reproducible.
    if isReturning,
       at - (s.memory.lastResurfacedAt ?? -.infinity) >= PetTuning.resurfaceMinGapMs,
       !s.sessions.values.contains(where: { $0.prompt != nil }) {
        let memories = s.memory.keepsakes.filter {
            $0.agentId == agentId && at - $0.at >= PetTuning.resurfaceMinAgeMs
        }
        if !memories.isEmpty {
            let pick = memories[Int(at) % memories.count]
            s.buddy.agentDrawing = pick
            s.buddy.agentDrawingUntil = at + PetTuning.drawShowMs
            s.buddy.agentDrawingIsMemory = true
            s.memory.lastResurfacedAt = at
        }
    }
    return s
}

private func handleAgentDrew(_ state: InternalState, at: Double, agentId: String, rows: [String], caption: String?) -> InternalState {
    var s = state
    let drawing = AgentDrawing(
        agentId: agentId,
        color: s.memory.agents[agentId]?.color,
        rows: rows,
        caption: caption,
        at: at
    )
    // The keepsake is unconditional — a parting gift is never lost to
    // timing. Only the held-up DISPLAY defers to a pending prompt (S1).
    s.memory.keepsakes.append(drawing)
    if s.memory.keepsakes.count > PetTuning.keepsakeCap {
        s.memory.keepsakes.removeFirst(s.memory.keepsakes.count - PetTuning.keepsakeCap)
    }
    if !s.sessions.values.contains(where: { $0.prompt != nil }) {
        s.buddy.agentDrawing = drawing
        s.buddy.agentDrawingUntil = at + PetTuning.drawShowMs
        s.buddy.agentDrawingIsMemory = nil
    }
    return s
}

private func handleAgentExpressed(_ state: InternalState, at: Double, agentId: String, emotion: String, intensity: String, motion: String?, say: String?, delivery: String?) -> InternalState {
    // S1: while ANY prompt is pending — any session, approval or notification —
    // agent expression is refused outright. The screen belongs to the trust
    // decision; the engine reports "deferred" back to the agent.
    guard !state.sessions.values.contains(where: { $0.prompt != nil }) else { return state }
    var s = state
    let lease = say != nil ? PetTuning.agentSayLeaseMs : PetTuning.agentExpressLeaseMs
    s.buddy.agentOverlay = AgentOverlay(
        agentId: agentId,
        color: s.memory.agents[agentId]?.color,
        emotion: emotion,
        intensity: intensity,
        motion: motion,
        say: say,
        delivery: delivery,
        until: at + lease
    )
    return s
}

private func handleSpeciesChanged(_ state: InternalState, species: String) -> InternalState {
    guard !species.isEmpty, state.buddy.pet.species != species else { return state }
    var s = state
    s.buddy.pet.species = species
    return s
}

private func handleReviewDismissed(_ state: InternalState) -> InternalState {
    guard state.buddy.lastCompleted != nil else { return state }
    var s = state
    s.buddy.lastCompleted = nil
    return s
}

private func handleErrorDismissed(_ state: InternalState, at: Double, sessionId: String) -> InternalState {
    guard state.sessions[sessionId]?.uhoh != nil || state.sessions[sessionId]?.state == .errored else { return state }
    var s = state
    s.sessions[sessionId]?.uhoh = nil
    s.sessions[sessionId]?.state = hasBlockingApproval(state.sessions[sessionId]) ? .needsConfirmation : .idle
    s.sessions[sessionId]?.workStartedAt = nil
    s.sessions[sessionId]?.lastWorkSignalAt = nil
    s.sessions[sessionId]?.currentTool = nil
    s.sessions[sessionId]?.currentHint = nil
    s.sessions[sessionId]?.lastActivityAt = at
    return s
}

// MARK: - Aggregation

private func aggregate(_ state: InternalState, now: Double) -> BuddyState {
    var buddy = state.buddy
    let allSessions = state.sessions.sorted { $0.key < $1.key }

    let waiting = allSessions.filter { $0.value.state == .needsConfirmation }
    let working = allSessions.filter { $0.value.state == .working && $0.value.uhoh == nil }
    let errored = allSessions.filter { $0.value.state != .needsConfirmation && ($0.value.state == .errored || $0.value.uhoh == .error || $0.value.uhoh == .hungry) }
    let thinking = allSessions.filter { $0.value.state != .needsConfirmation && ($0.value.state == .thinking || $0.value.uhoh == .stuck) }

    buddy.sessions = SessionCounts(
        total: allSessions.count,
        running: working.count + waiting.count + thinking.count,
        waiting: waiting.count
    )

    let highestPrompt = waiting.min(by: { ($0.value.prompt?.arrivedAt ?? .infinity) < ($1.value.prompt?.arrivedAt ?? .infinity) })?.value.prompt
    buddy.prompt = highestPrompt

    // Build per-session breakdown for the popover. Order: needsConfirmation
    // (oldest prompt first) → errored (oldest workStartedAt) → working (oldest
    // workStartedAt) → idle (most recent first). Cap at 6 to match firmware
    // tama.lines[6] capacity.
    let waitingOrdered = waiting
        .sorted { ($0.value.prompt?.arrivedAt ?? .infinity) < ($1.value.prompt?.arrivedAt ?? .infinity) }
    let erroredOrdered = errored
        .sorted { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) }
    let workingOrdered = working
        .sorted { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) }
    let idleOrdered = allSessions
        .filter { $0.value.state == .idle && $0.value.uhoh == nil }
        .sorted { $0.value.lastActivityAt > $1.value.lastActivityAt }
    let thinkingOrdered = thinking  // allSessions is key-sorted; filter keeps order
    let combined = waitingOrdered + erroredOrdered + thinkingOrdered + workingOrdered + idleOrdered
    var activeSnapshots: [SessionSnapshot] = []
    activeSnapshots.reserveCapacity(min(combined.count, 6))
    for (id, sess) in combined.prefix(6) {
        activeSnapshots.append(SessionSnapshot(
            id: id,
            source: sess.source,
            state: sess.uhoh == nil || sess.state == .needsConfirmation ? sess.state : (sess.uhoh == .stuck ? .thinking : .errored),
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            currentTool: sess.currentTool
        ))
    }
    buddy.activeSessions = activeSnapshots

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

    // Project the oldest thinking session — same shape, but for the calm
    // "agent is thinking hard" surface (no Dismiss, no sound).
    let firstThinkingSession = thinking.min(by: { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) })
    buddy.firstThinking = firstThinkingSession.map { id, sess in
        return ThinkingSession(
            id: id,
            source: sess.source,
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            tool: sess.currentTool,
            hint: sess.currentHint,
            workStartedAt: sess.workStartedAt,
            lastWorkSignalAt: sess.lastWorkSignalAt
        )
    }

    // The review surface clears as soon as a new prompt arrives (live state takes
    // visual primacy) or work resumes (the user reset the loop). It survives the
    // 4-second celebrate window into idle so the user can see what finished.
    if !waiting.isEmpty || !working.isEmpty || !thinking.isEmpty {
        buddy.lastCompleted = nil
    }

    // Default — gets overwritten below in the busy branch when present.
    buddy.currentActivityKind = nil
    buddy.effortTier = nil

    // S1 belt and braces: the reducer already refuses agentExpressed while a
    // prompt is pending, but a prompt arriving mid-lease must also evict the
    // overlay and any held-up drawing — agent content and trust decisions
    // never share the screen. (The drawing's keepsake survives in memory.)
    if !waiting.isEmpty {
        buddy.agentOverlay = nil
        buddy.agentDrawing = nil
        buddy.agentDrawingUntil = nil
        buddy.agentDrawingIsMemory = nil
    }

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
        let stakes = cardStakes(tool: prompt.tool, hint: prompt.hint)
        creature.card = CreatureCard(id: prompt.id, tool: prompt.tool, gloss: prompt.hint,
                                     stakes: stakes, index: 0, count: waiting.count, isApproval: prompt.isApproval)
        creature.nudgeRung = state.nudges[prompt.id]?.rung ?? 0
        if creature.focus && stakes != .careful { creature.nudgeRung = 0 }
        buddy.msg = shortMsg(tool: prompt.tool, hint: prompt.hint, source: prompt.source ?? "")
    } else if !errored.isEmpty || !thinking.isEmpty {
        creature.state = .uhoh
        let primary = firstErroredSession?.value ?? firstThinkingSession?.value
        creature.uhoh = primary?.uhoh ?? (errored.isEmpty ? .stuck : .error)
        let label = creature.uhoh == .stuck ? "Thinking" : "Error"
        buddy.msg = primary?.currentTool.flatMap { $0.isEmpty ? nil : "\(label): \($0)" } ?? label
    } else if let until = buddy.celebrateUntil, now < until {
        creature.state = .done
        creature.cheer = state.doneSize ?? .hop
        buddy.msg = buddy.lastCompleted?.tool.map { "Done: \($0)" } ?? ""
    } else if let primary = workingOrdered.first?.value {
        creature.state = .working
        let tier = effortTier(for: primary, elapsedMs: primary.workStartedAt.map { now - $0 } ?? 0)
        buddy.effortTier = tier
        creature.effort = tier == .grinding ? .grinding : tier == .hard ? .hard : .light
        buddy.currentActivityKind = primary.currentActivityKind
        buddy.msg = primary.currentTool.map { shortMsg(tool: $0, hint: primary.currentHint ?? "", source: primary.source) } ?? ""
    } else {
        creature.state = hasConnected || buddy.mood == .expectant ? .idle : .asleep
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
    // Legacy fields are projections of the creature; nothing else writes them.
    buddy.pet.state = legacyPetState(from: creature)
    buddy.celebrateIntensity = creature.cheer?.intensity
    buddy.lastSignal = creature.state == .asleep ? nil : legacyPetState(from: creature, includingOverlay: false).rawValue

    return buddy
}

/// The agent's own report wins; otherwise elapsed span and error count set
/// the tier. Errors escalate faster than time — three failures IS a grind,
/// however short.
private func effortTier(for session: Session, elapsedMs: Double) -> EffortTier {
    if let reported = session.reportedEffort { return reported }
    if elapsedMs >= PetTuning.effortGrindingMinMs || session.errorCount >= 3 { return .grinding }
    if elapsedMs >= PetTuning.effortHardMinMs || session.errorCount >= 2 { return .hard }
    if elapsedMs < PetTuning.effortLightMaxMs && session.errorCount == 0 { return .light }
    return .normal
}

// MARK: - Helpers

private func setPrompt(_ state: InternalState, at: Double, sessionId: String, requestId: String, tool: String, hint: String, sessionLabel: String?, source: String?, isApproval: Bool) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at)

    let effectiveSource = source ?? s.sessions[sessionId]?.source
    let kind = activityKind(tool: tool, hint: hint)
    let prompt = Prompt(id: requestId, tool: tool, hint: hint, arrivedAt: at, sessionLabel: sessionLabel, source: effectiveSource, isApproval: isApproval, activityKind: kind)
    s.sessions[sessionId]?.state = .needsConfirmation
    s.sessions[sessionId]?.prompt = prompt

    let msg = shortMsg(tool: tool, hint: hint, source: effectiveSource ?? "")
    s.buddy.entries = Array(([msg] + s.buddy.entries).prefix(10))
    return s
}

private func touchSession(_ state: inout InternalState, sessionId: String, at: Double, source: String? = nil) {
    if var session = state.sessions[sessionId] {
        session.lastActivityAt = at
        if let source { session.source = source }
        state.sessions[sessionId] = session
    } else {
        state.sessions[sessionId] = Session(
            source: source ?? "unknown",
            state: .idle,
            prompt: nil,
            cwd: nil,
            lastActivityAt: at,
            workStartedAt: nil
        )
    }
}

private func shortMsg(tool: String, hint: String, source: String) -> String {
    let base = !source.isEmpty && source != "other" ? "[\(source)] \(tool)" : tool
    if hint.isEmpty { return base }
    let short = hint.count <= 60 ? hint : String(hint.prefix(57)) + "..."
    return "\(base): \(short)"
}

func formatDuration(_ ms: Double) -> String {
    let seconds = Int(ms / 1000)
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    let remSeconds = seconds % 60
    return "\(minutes)m \(remSeconds)s"
}

// MARK: - Creature Policy

struct CheerThresholds: Sendable, Equatable {
    var danceErrors = 3
    var danceSpanMs: Double = 1_200_000
    var cheerErrors = 1
    var cheerSpanMs: Double = 300_000
    var hopMs: Double = 1500
    var cheerMs: Double = 2500
    var danceMs: Double = 4000
    var foldMs: Double = 3000
    static let defaults = CheerThresholds()

    func size(errors: Int, span: Double, effort: EffortTier) -> CheerSize {
        if errors >= danceErrors || (span >= danceSpanMs && errors >= 1) || effort == .grinding { return .dance }
        if errors >= cheerErrors || span >= cheerSpanMs || effort == .hard { return .cheer }
        return .hop
    }

    func duration(_ size: CheerSize) -> Double {
        switch size { case .hop: hopMs; case .cheer: cheerMs; case .dance: danceMs }
    }
}

struct NudgeTiming: Sendable, Equatable {
    var t1: Double = 180_000
    var t2: Double = 300_000
    var rung2RateLimit: Double = 600_000
    static let defaults = NudgeTiming()
}

struct CardNudge: Sendable, Equatable {
    var rung = 0
    var nextAt: Double
    var dismissals = 0
    var snoozed = false
    var lastRung2At: Double?
}

/// Destructive-shell classifier. Literal fragments are plain `contains`;
/// only the pipe-to-shell shapes need a regex, compiled once.
private enum CardStakesPolicy {
    static let carefulLiterals = ["rm -rf", "rm -r ", "sudo ", "git push --force", "git push -f", "mkfs", "dd if=", "chmod 777"]
    static let carefulRegexes: [NSRegularExpression] = [#"curl\b[^\n]*\|\s*sh\b"#, #"wget\b[^\n]*\|\s*sh\b"#]
        .map { try! NSRegularExpression(pattern: $0) }
    /// Cursor's read-only tool names; Claude/Codex names go through `activityKind`.
    static let readOnlyCursorTools: Set<String> = ["ls", "read_file", "list_dir", "list_directory", "file_search", "grep_search", "codebase_search", "search"]
    static let controlCharacters = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\t"))
}

func cardStakes(tool: String, hint: String) -> Stakes {
    if hint.rangeOfCharacter(from: CardStakesPolicy.controlCharacters) != nil { return .careful }
    if CardStakesPolicy.carefulLiterals.contains(where: { hint.contains($0) }) { return .careful }
    let range = NSRange(location: 0, length: (hint as NSString).length)
    if CardStakesPolicy.carefulRegexes.contains(where: { $0.firstMatch(in: hint, range: range) != nil }) { return .careful }
    if activityKind(tool: tool, hint: hint) == .read || CardStakesPolicy.readOnlyCursorTools.contains(tool.lowercased()) { return .fine }
    return .checkIt
}

/// The orb's story line (Phase 1: the last hint; Phase 3 replaces it with a
/// moment). Capped for the device bubble.
private func giftLine(forHint hint: String?) -> String {
    ("done: " + (hint ?? "")).prefix(utf8Bytes: 40)
}

private func setBubble(_ s: inout InternalState, _ line: String, at: Double) {
    s.buddy.creature.bubble = line
    s.bubbleUntil = at + 4000
}

private func enterUhoh(_ s: inout InternalState, sessionId: String, kind: UhohKind, at: Double) {
    if s.sessions[sessionId]?.uhoh != kind {
        let line: String
        switch kind {
        case .error: line = s.sessions[sessionId]?.currentHint?.contains("build") == true ? "build failed" : "something broke"
        case .stuck: line = "might be going in circles"
        case .hungry: line = "hungry"
        }
        setBubble(&s, line, at: at)
    }
    s.sessions[sessionId]?.uhoh = kind
    if !hasBlockingApproval(s.sessions[sessionId]) {
        s.sessions[sessionId]?.state = kind == .stuck ? .thinking : .errored
        s.sessions[sessionId]?.prompt = nil
    }
}

private func collectGift(_ s: inout InternalState, at: Double) {
    if s.buddy.creature.gift, let line = s.buddy.creature.giftLine { setBubble(&s, line, at: at) }
    s.buddy.creature.gift = false
    s.buddy.creature.giftLine = nil
}

private func dismissNudge(_ state: InternalState, at: Double) -> InternalState {
    var s = state
    guard let card = s.buddy.creature.card,
          let id = s.sessions.first(where: { $0.value.prompt?.id == card.id })?.key,
          var nudge = s.nudges[card.id] else { return s }
    nudge.dismissals += 1
    nudge.rung = 0
    nudge.nextAt = at + s.nudgeTiming.t1 / pow(2, Double(nudge.dismissals))
    if nudge.dismissals >= 3 {
        nudge.snoozed = true
        s.snoozedTools[id, default: []].insert(card.tool)
        setBubble(&s, "okay, I'll hush about that", at: at)
    }
    s.nudges[card.id] = nudge
    return s
}

/// Timers use only supplied event time. Each card owns its ladder even when
/// another session's older card is currently on top.
private func updateCreatureTimers(_ s: inout InternalState, event: BuddyEvent) {
    if case .staleTick = event, let until = s.bubbleUntil, event.at >= until {
        s.buddy.creature.bubble = nil
        s.bubbleUntil = nil
    }
    let liveIds = Set(s.sessions.values.compactMap { $0.prompt?.id })
    // Hot path: nothing to advance or garbage-collect without a card.
    if liveIds.isEmpty && s.nudges.isEmpty && s.snoozedTools.isEmpty { return }
    s.nudges = s.nudges.filter { liveIds.contains($0.key) }
    s.snoozedTools = s.snoozedTools.filter { s.sessions[$0.key] != nil }
    for (id, session) in s.sessions {
        guard let prompt = session.prompt else { continue }
        let stakes = cardStakes(tool: prompt.tool, hint: prompt.hint)
        var nudge = s.nudges[prompt.id] ?? CardNudge(nextAt: prompt.arrivedAt + s.nudgeTiming.t1)
        nudge.snoozed = s.snoozedTools[id]?.contains(prompt.tool) == true
        if nudge.snoozed || (s.buddy.creature.focus && stakes != .careful) {
            nudge.rung = 0
        } else if case .staleTick = event, event.at >= nudge.nextAt {
            if nudge.rung == 0 {
                nudge.rung = 1
                nudge.nextAt = event.at + s.nudgeTiming.t2 / pow(2, Double(nudge.dismissals))
            } else if stakes == .careful && nudge.rung == 1 &&
                        event.at - (nudge.lastRung2At ?? -.infinity) >= s.nudgeTiming.rung2RateLimit {
                nudge.rung = 2
                nudge.lastRung2At = event.at
                nudge.nextAt = event.at + s.nudgeTiming.rung2RateLimit
            }
        }
        if nudge != s.nudges[prompt.id] { s.nudges[prompt.id] = nudge }
    }
}
