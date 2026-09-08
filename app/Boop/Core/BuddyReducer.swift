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

    var version: Int { buddy.version }

    static func initial(staleMs: Double, celebrateDurationMs: Double, workStallTimeoutMs: Double = 300_000, approvalTimeoutMs: Double = 290_000) -> InternalState {
        InternalState(buddy: .initial, sessions: [:], staleMs: staleMs, celebrateDurationMs: celebrateDurationMs, workStallTimeoutMs: workStallTimeoutMs, approvalTimeoutMs: approvalTimeoutMs)
    }
}

// MARK: - Reducer

func reduce(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    var next = reduceInner(state, event)
    guard next != state else { return state }
    next.buddy.version = state.buddy.version + 1
    next.buddy.updatedAt = event.at
    next.buddy = aggregate(next)
    return next
}

private func reduceInner(_ state: InternalState, _ event: BuddyEvent) -> InternalState {
    switch event {
    case .sessionStarted(let at, let sessionId, let source, let cwd):
        return handleSessionStarted(state, at: at, sessionId: sessionId, source: source, cwd: cwd)
    case .sessionEnded(_, let sessionId):
        return handleSessionEnded(state, sessionId: sessionId)
    case .requestArrived(let at, let sessionId, let requestId, let tool, let hint, let sessionLabel):
        return handleRequestArrived(state, at: at, sessionId: sessionId, requestId: requestId, tool: tool, hint: hint, sessionLabel: sessionLabel)
    case .requestCleared(let at, let sessionId):
        return handleRequestCleared(state, at: at, sessionId: sessionId)
    case .activitySignal(let at, let sessionId, let source, let signal, let tool, let hint):
        return handleActivitySignal(state, at: at, sessionId: sessionId, source: source, signal: signal, tool: tool, hint: hint)
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

private func handleActivitySignal(_ state: InternalState, at: Double, sessionId: String, source: String, signal: ActivitySignalKind, tool: String?, hint: String?) -> InternalState {
    var s = state
    observePresence(&s, at: at)
    touchSession(&s, sessionId: sessionId, at: at, source: source)

    switch signal {
    case .startWorking, .keepWorking:
        // A parked approval outranks a work signal: the hook is still blocked
        // on an answer, so leave the prompt (and .needsConfirmation) alone and
        // only refresh liveness.
        if hasBlockingApproval(s.sessions[sessionId]) {
            s.sessions[sessionId]?.lastWorkSignalAt = at
            if let tool, !tool.isEmpty {
                s.sessions[sessionId]?.lastTool = tool
                s.sessions[sessionId]?.lastHint = hint
            }
            return s
        }
        if s.sessions[sessionId]?.state == .needsConfirmation {
            s.sessions[sessionId]?.prompt = nil
        }
        // Preserve workStartedAt when transitioning from .thinking → .working
        // (the work paused, didn't restart). Only stamp a new start time when
        // entering .working from a truly inactive state (.idle/.errored/etc).
        let priorState = s.sessions[sessionId]?.state
        if priorState != .working && priorState != .thinking {
            s.sessions[sessionId]?.workStartedAt = at
        }
        s.sessions[sessionId]?.state = .working
        s.sessions[sessionId]?.lastWorkSignalAt = at
        if let tool, !tool.isEmpty {
            s.sessions[sessionId]?.lastTool = tool
            s.sessions[sessionId]?.lastHint = hint
            s.sessions[sessionId]?.currentTool = tool
            s.sessions[sessionId]?.currentHint = hint
            s.sessions[sessionId]?.currentActivityKind = activityKind(tool: tool, hint: hint ?? "")
        }
    case .stopWorking:
        // Same rule as start/keepWorking above: a parked approval still has a
        // hook blocked on it, so an idle notification (e.g. Claude Code's
        // idle_prompt firing mid-wait) must not withdraw the card — that would
        // silently passthrough the blocked caller.
        if hasBlockingApproval(s.sessions[sessionId]) {
            return s
        }
        s.sessions[sessionId]?.state = .idle
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.workStartedAt = nil
        s.sessions[sessionId]?.lastWorkSignalAt = nil
        s.sessions[sessionId]?.currentTool = nil
        s.sessions[sessionId]?.currentHint = nil
        s.sessions[sessionId]?.currentActivityKind = nil
    case .celebrate:
        let session = s.sessions[sessionId]
        let duration = session?.workStartedAt.map { at - $0 }
        let completedTool = tool ?? session?.lastTool
        let completedHint = hint ?? session?.lastHint
        let completedKind: ActivityKind = {
            if let t = completedTool { return activityKind(tool: t, hint: completedHint ?? "") }
            return .work
        }()
        s.sessions[sessionId]?.state = .idle
        s.sessions[sessionId]?.prompt = nil
        s.sessions[sessionId]?.workStartedAt = nil
        s.sessions[sessionId]?.lastWorkSignalAt = nil
        s.sessions[sessionId]?.currentTool = nil
        s.sessions[sessionId]?.currentHint = nil
        s.sessions[sessionId]?.currentActivityKind = nil
        // Payoff scaling: joy proportional to the struggle. A long or
        // error-pocked stretch earns the big celebration; a 30-second task a
        // modest hop. Never scaled by approvals (S9).
        let errors = session?.errorCount ?? 0
        s.buddy.celebrateIntensity = {
            if (duration ?? 0) >= PetTuning.celebrateHugeMinMs || errors >= 2 { return 3 }
            if (duration ?? 0) >= PetTuning.celebrateBigMinMs || errors >= 1 { return 2 }
            return 1
        }()
        s.memory.lifetimeCelebrations += 1
        s.sessions[sessionId]?.errorCount = 0
        s.sessions[sessionId]?.reportedEffort = nil
        s.buddy.celebrateUntil = at + s.celebrateDurationMs
        s.buddy.lastTaskDurationMs = duration
        s.buddy.lastCompletionAt = at
        s.buddy.lastCompleted = CompletedTask(
            id: "\(sessionId)_\(Int(at))",
            tool: completedTool,
            hint: completedHint,
            source: source,
            sessionLabel: session?.cwd.flatMap { ($0 as NSString).lastPathComponent },
            durationMs: duration,
            completedAt: at,
            activityKind: completedKind
        )
    case .error:
        // Preserve currentTool/currentHint and workStartedAt — we want the error
        // card to show "what failed" and "for how long".
        s.sessions[sessionId]?.state = .errored
        s.sessions[sessionId]?.errorCount += 1
        s.sessions[sessionId]?.prompt = nil
        if let tool, !tool.isEmpty {
            s.sessions[sessionId]?.lastTool = tool
            s.sessions[sessionId]?.lastHint = hint
            s.sessions[sessionId]?.currentTool = tool
            s.sessions[sessionId]?.currentHint = hint
            s.sessions[sessionId]?.currentActivityKind = activityKind(tool: tool, hint: hint ?? "")
        }
    }

    let signalDetail: String = {
        if let tool, !tool.isEmpty {
            return shortMsg(tool: tool, hint: hint ?? "", source: source)
        }
        return "[\(source)] \(signal.rawValue)"
    }()
    s.buddy.entries = Array(([signalDetail] + s.buddy.entries).prefix(10))
    return s
}

private func handleStaleTick(_ state: InternalState, now: Double) -> InternalState {
    var changed = false
    var s = state

    if let until = s.buddy.celebrateUntil, now >= until {
        s.buddy.celebrateUntil = nil
        s.buddy.celebrateIntensity = nil
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
            s.sessions[id]?.state = .thinking
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
    s.buddy.pet = Pet(state: s.buddy.pet.state, species: species)
    return s
}

private func handleReviewDismissed(_ state: InternalState) -> InternalState {
    guard state.buddy.lastCompleted != nil else { return state }
    var s = state
    s.buddy.lastCompleted = nil
    return s
}

private func handleErrorDismissed(_ state: InternalState, at: Double, sessionId: String) -> InternalState {
    guard state.sessions[sessionId]?.state == .errored else { return state }
    var s = state
    s.sessions[sessionId]?.state = .idle
    s.sessions[sessionId]?.workStartedAt = nil
    s.sessions[sessionId]?.lastWorkSignalAt = nil
    s.sessions[sessionId]?.currentTool = nil
    s.sessions[sessionId]?.currentHint = nil
    s.sessions[sessionId]?.lastActivityAt = at
    return s
}

// MARK: - Aggregation

private func aggregate(_ state: InternalState) -> BuddyState {
    var buddy = state.buddy
    let allSessions = Array(state.sessions)

    let waiting = allSessions.filter { $0.value.state == .needsConfirmation }
    let working = allSessions.filter { $0.value.state == .working }
    let errored = allSessions.filter { $0.value.state == .errored }
    let thinking = allSessions.filter { $0.value.state == .thinking }

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
        .filter { $0.value.state == .idle }
        .sorted { $0.value.lastActivityAt > $1.value.lastActivityAt }
    let combined = waitingOrdered + erroredOrdered + workingOrdered + idleOrdered
    var activeSnapshots: [SessionSnapshot] = []
    activeSnapshots.reserveCapacity(min(combined.count, 6))
    for (id, sess) in combined.prefix(6) {
        activeSnapshots.append(SessionSnapshot(
            id: id,
            source: sess.source,
            state: sess.state,
            sessionLabel: sess.cwd.flatMap { ($0 as NSString).lastPathComponent },
            currentTool: sess.currentTool
        ))
    }
    buddy.activeSessions = activeSnapshots

    // Project the oldest errored session for the popover Error card. Carries the
    // session id so dismissError(sessionId:) can target a specific one.
    let firstErroredSession = errored.min(by: { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) })
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
        lastHeartbeatAt: allSessions.map(\.value.lastActivityAt).max()
    )

    if !hasConnected {
        // Expectant is the one thing that wakes the pet without a session:
        // around the user's usual start hour it sits up and watches the door.
        let state: PetState = buddy.mood == .expectant ? .idle : .sleep
        buddy.pet = Pet(state: state, species: buddy.pet.species)
        buddy.msg = ""
        buddy.lastSignal = nil
    } else if !waiting.isEmpty {
        buddy.pet = Pet(state: .attention, species: buddy.pet.species)
        if let p = highestPrompt {
            buddy.msg = shortMsg(tool: p.tool, hint: p.hint, source: p.source ?? "")
        }
        buddy.lastSignal = "attention"
    } else if !errored.isEmpty {
        // Error sits between attention and busy. A live approval still wins (already
        // handled above), but a failed session takes priority over busy peers.
        buddy.pet = Pet(state: .error, species: buddy.pet.species)
        let oldest = errored.min(by: { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) })?.value
        if let tool = oldest?.currentTool, !tool.isEmpty {
            buddy.msg = "Error: \(tool)"
        } else {
            buddy.msg = "Error"
        }
        buddy.lastSignal = "error"
    } else if !working.isEmpty {
        // New work consumes the celebration. Leaving celebrateUntil set meant
        // that when this work finished inside the original 4s window, the
        // aggregate fell back into the celebrate branch and threw a SECOND
        // party for a completion already shown — replaying the sound and
        // re-opening the popover, with msg empty and lastCompleted wiped, so
        // it was a celebration with nothing to show.
        buddy.celebrateUntil = nil
        buddy.celebrateIntensity = nil
        buddy.pet = Pet(state: .busy, species: buddy.pet.species)
        // Primary working session = oldest workStartedAt (longest running). Surface its
        // current tool/hint so the user can see what the agent is doing right now.
        let primary = working.min(by: { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) })?.value
        if let tool = primary?.currentTool, !tool.isEmpty {
            buddy.msg = shortMsg(tool: tool, hint: primary?.currentHint ?? "", source: primary?.source ?? "")
        } else {
            buddy.msg = ""
        }
        buddy.currentActivityKind = primary?.currentActivityKind
        // Effort shows in *expression*, not judgment: the pet strains
        // alongside a hard task; it is never disappointed at anyone.
        if let primary {
            let elapsed = primary.workStartedAt.map { buddy.updatedAt - $0 } ?? 0
            buddy.effortTier = effortTier(for: primary, elapsedMs: elapsed)
        }
        buddy.lastSignal = "busy"
    } else if !thinking.isEmpty {
        // Calm "the agent is thinking hard" state — silent past the work-stall
        // threshold but presumed alive (e.g. an extended-thinking turn or a
        // long-running model reply). No alert, no Dismiss.
        buddy.pet = Pet(state: .thinking, species: buddy.pet.species)
        let oldest = thinking.min(by: { ($0.value.workStartedAt ?? .infinity) < ($1.value.workStartedAt ?? .infinity) })?.value
        if let tool = oldest?.currentTool, !tool.isEmpty {
            buddy.msg = "Thinking: \(tool)"
        } else {
            buddy.msg = "Thinking"
        }
        buddy.lastSignal = "thinking"
    } else if let until = buddy.celebrateUntil, buddy.updatedAt < until {
        buddy.pet = Pet(state: .celebrate, species: buddy.pet.species)
        // Show the just-completed task on the device's msg line during celebrate.
        // The desktop popover ignores msg and renders ReviewCardView instead.
        if let lc = buddy.lastCompleted, let tool = lc.tool {
            buddy.msg = "Done: \(tool)\(lc.durationMs.map { " (\(formatDuration($0)))" } ?? "")"
        } else {
            buddy.msg = ""
        }
        buddy.lastSignal = "celebrate"
    } else {
        buddy.pet = Pet(state: .idle, species: buddy.pet.species)
        // Idle keeps the completion summary on the device's msg line until a new
        // prompt or work signal arrives (handled by clearing lastCompleted above
        // and by checking it here).
        if let lc = buddy.lastCompleted, let tool = lc.tool {
            buddy.msg = "Done: \(tool)\(lc.durationMs.map { " (\(formatDuration($0)))" } ?? "")"
        } else {
            buddy.msg = ""
        }
        buddy.celebrateUntil = nil
        buddy.celebrateIntensity = nil
        buddy.lastSignal = "idle"
    }

    // Boop overlay: a recent device boop puts calm states in heart-eyes.
    // Mirrors the firmware — attention/error always win (urgency over
    // affection), and a sleeping pet does its sleep-peek on device instead,
    // so sleep stays sleep here too. msg/lastSignal keep the base state's
    // values so the underlying activity context survives the flash.
    if let until = buddy.affectionUntil, buddy.updatedAt < until {
        switch buddy.pet.state {
        case .idle, .busy, .thinking, .celebrate:
            buddy.pet = Pet(state: .heart, species: buddy.pet.species)
        case .sleep, .attention, .error, .heart:
            break
        }
    }

    // Return-greeting overlay: same shape as the boop overlay above. Reusing
    // .heart keeps the wire compatible with already-flashed firmware (an
    // unknown pet string would fall to its default); the separate greet flag
    // in the heartbeat lets newer firmware do a dedicated animation.
    if let until = buddy.greetUntil, buddy.updatedAt < until {
        switch buddy.pet.state {
        case .idle, .busy, .thinking, .celebrate:
            buddy.pet = Pet(state: .heart, species: buddy.pet.species)
        case .sleep, .attention, .error, .heart:
            break
        }
    }

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
