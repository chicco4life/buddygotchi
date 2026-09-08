import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    let serverHealth: ServerHealth?
    var onUserInteraction: (() -> Void)? = nil
    var onOpenOnboarding: () -> Void = {}
    private var setupCompleted: Bool { engine.boolSetting(DefaultsKey.setupCompleted) }
    private var buddyName: String { engine.buddyName }
    @AppStorage(DefaultsKey.showMenuHint) private var showMenuHint = false
    @State private var showingShelf = false
    private var agentDrawingsEnabled: Bool { engine.boolSetting(DefaultsKey.agentDrawingsEnabled, fallback: true) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        engine: BuddyEngine,
        esp32Output: ESP32Output,
        serverHealth: ServerHealth? = nil,
        onUserInteraction: (() -> Void)? = nil,
        onOpenOnboarding: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.esp32Output = esp32Output
        self.serverHealth = serverHealth
        self.onUserInteraction = onUserInteraction
        self.onOpenOnboarding = onOpenOnboarding
    }

    var body: some View {
        ZStack {
            BuddyTheme.paper.ignoresSafeArea()

            Group {
                if !setupCompleted {
                    unfinishedSetupView
                } else if showingShelf {
                    KeepsakeShelfView(engine: engine, isPresented: $showingShelf)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    liveView
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .buddyEase(0.2), value: showingShelf)
        .onHover { hovering in
            if hovering { onUserInteraction?() }
        }
    }

    private var unfinishedSetupView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text(BuddyCopy.Onboarding.finishMeeting)
                    .font(.buddy(15, weight: .semibold))
                    .foregroundStyle(BuddyTheme.ink)
                    .multilineTextAlignment(.center)
                Text(BuddyCopy.Onboarding.finishMeetingSubtitle)
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Button(BuddyCopy.Onboarding.meetBuddy, action: onOpenOnboarding)
                .buttonStyle(BuddyPrimaryButtonStyle())

            Spacer()
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.unfinishedSetupHeight)

    }

    // MARK: - Live View

    // The popover is the approve/deny surface plus a health readout. Anything the
    // device says better does not belong here.
    private var liveView: some View {
        VStack(spacing: 0) {
            headerRow
            CreatureView(creature: engine.state.creature, cosmetic: engine.state.cosmetic, paused: !engine.popoverVisible)
                .frame(height: 180)
            if let bubble = engine.state.creature.bubble, engine.state.creature.card == nil {
                Text(bubble).font(.buddy(12)).foregroundStyle(BuddyTheme.ink)
                    .padding(10).buddySurface()
            }
            if engine.state.creature.gift && engine.state.creature.card == nil {
                Button(action: { engine.collectArrived() }) {
                    HStack {
                        Circle().fill(BuddyTheme.amber.gradient).frame(width: 18, height: 18)
                        Text(engine.state.creature.giftLine ?? BuddyCopy.phase7("collect", language: engine.state.language))
                            .font(.buddy(12))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(BuddyPlainButtonStyle())
            }
            if let tool = engine.teachTool, engine.state.creature.card == nil {
                HStack {
                    Text(TeachCatalog.line(tool: tool, language: engine.state.language) ?? tool).font(.buddy(11))
                    Button { Task { await engine.dismissTeach(tool: tool) } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(BuddyCopy.phase7("quietTool", language: engine.state.language))
                }.foregroundStyle(BuddyTheme.inkSoft)
            }

            if showMenuHint {
                Spacer().frame(height: 6)
                Text(BuddyCopy.Onboarding.menuHint)
                    .font(.buddy(9.5, weight: .semibold))
                    .foregroundStyle(BuddyTheme.amberInk)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        showMenuHint = false
                    }
            }

            // Agent expression (System E). Never rendered while a prompt is
            // pending — the reducer guarantees the overlay is gone by then —
            // and always labeled with who is speaking.
            if let overlay = engine.state.agentOverlay {
                Spacer().frame(height: 8)
                AgentExpressionRow(overlay: overlay)
                    .transition(.opacity)
            }

            // A drawing the pet is holding up (E4) — same S1 guarantee.
            // The settings toggle also silences resurfaced memories here.
            if let drawing = engine.state.agentDrawing, agentDrawingsEnabled {
                Spacer().frame(height: 8)
                AgentDrawingCard(drawing: drawing, isMemory: engine.state.agentDrawingIsMemory == true)
                    .transition(.opacity)
            }

            if let card = engine.state.creature.card {
                NeedsYouCard(language: engine.state.language, card: card, approve: { engine.resolveApproval(requestId: card.id, decision: .allow) }, deny: { engine.resolveApproval(requestId: card.id, decision: .deny) })
                    .padding(.top, 12)
            }
            if let recap = engine.state.recap, engine.state.prompt == nil {
                RecapView(language: engine.state.language, recap: recap).padding(.top, 12)
            }

            let rows = activityRows
            if !rows.isEmpty {
                Spacer().frame(height: 12)
                ScrollView {
                    ActivityList(rows: rows, maxRows: rows.count)
                }.frame(height: min(CGFloat(rows.count) * 48, 144))
                    .transition(.opacity)
            } else if engine.state.sessions.total == 0 {
                Spacer().frame(height: 12)
                EmptyAgentsView()
                    .transition(.opacity)
            }

            Spacer(minLength: 12)

            footerRow
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth)
        .frame(minHeight: BuddyTheme.liveViewHeight)
        .animation(reduceMotion ? nil : Animation.buddyBloom(), value: engine.state.prompt != nil)

    }

    /// Name, state, and the way out. One row instead of a pill and a footer.
    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(statusName)
                .font(.buddy(13, weight: .semibold))
                .foregroundStyle(BuddyTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            Text(stateLabel)
                .font(.buddy(9.5, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateFill.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(stateFill.opacity(0.35), lineWidth: BuddyTheme.hairlineWidth))
                .foregroundStyle(stateInk)
                .fixedSize()
                .accessibilityLabel("\(statusName), \(stateLabel)")

            Spacer(minLength: 8)

            // The museum door: only appears once there's something on the
            // shelf — a discovered surface, not an announced feature.
            if !engine.petMemory.keepsakes.isEmpty {
                Button(action: { showingShelf = true }) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .buttonStyle(BuddyPlainButtonStyle())
                .accessibilityLabel(BuddyCopy.shared.popover.keepsakeShelf)
            }

            Button(action: { CompanionWindows.shared.settings(engine: engine, device: esp32Output, onOnboarding: onOpenOnboarding) }) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(BuddyTheme.inkSoft)
            }
            .buttonStyle(BuddyPlainButtonStyle())
            .accessibilityLabel(BuddyCopy.settings)
        }
    }

    /// Connection health, and the server warning when there is one — the warning
    /// replaces the status rather than stacking another row on top of it.
    private var footerRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(serverWarning == nil ? statusColor : BuddyTheme.clayInk)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            Text(serverWarning ?? (engine.state.desktop.status == .connected ? BuddyCopy.book(language: engine.state.language).common.connected : BuddyCopy.phase7("disconnected", language: engine.state.language)))
                .font(.buddy(11))
                .foregroundStyle(serverWarning == nil ? BuddyTheme.inkFaint : BuddyTheme.clayInk)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(BuddyCopy.growthLabel(engine.state.growth)).font(.buddy(11))
            Toggle(BuddyCopy.phase7("focus", language: engine.state.language), isOn: Binding(get: { engine.state.creature.focus }, set: { engine.focusToggled(on: $0) }))
                .toggleStyle(.button).font(.buddy(10))
            Menu {
                Button(BuddyCopy.phase7("recap", language: engine.state.language)) { Task { _ = try? await engine.makeRecap() } }
                Button(BuddyCopy.phase7("profile", language: engine.state.language)) { CompanionWindows.shared.profile(engine: engine) }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize()

        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connectionAccessibilityLabel)
    }

    /// One line per active session, plus a line for a just-finished task. The
    /// reducer clears `lastCompleted` on the next prompt or work signal, so the
    /// done line ages out on its own.
    private var activityRows: [ActivityRow] {
        engine.state.activeSessions.map { ActivityRow(session: $0, state: engine.state) }
    }

    private var serverWarning: String? {
        guard let serverHealth else { return nil }
        if case .failed(let reason) = serverHealth.status {
            return BuddyCopy.shared.popover.serverWarningTemplate
                .replacingOccurrences(of: "{port}", with: "\(BuddyConfig.default.httpPort)")
                .replacingOccurrences(of: "{reason}", with: reason)
        }
        return nil
    }

    private var statusName: String {
        let trimmed = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? engine.state.pet.species : trimmed
    }

    private var connectionAccessibilityLabel: String {
        let status = engine.state.desktop.status.rawValue
        guard engine.state.sessions.total > 0 else {
            return BuddyCopy.shared.popover.desktopStatusTemplate.replacingOccurrences(of: "{status}", with: status)
        }
        let sessions = BuddyCopy.shared.popover.activeSessionsTemplate.replacingOccurrences(of: "{count}", with: "\(engine.state.sessions.running)")
        return BuddyCopy.shared.popover.desktopStatusWithSessionsTemplate
            .replacingOccurrences(of: "{status}", with: status)
            .replacingOccurrences(of: "{sessions}", with: sessions)
    }

    private var pill: CreaturePill { CreaturePill.table[engine.state.creature.state]! }
    private var stateInk: Color { pill.ink }
    private var stateFill: Color { pill.fill }
    private var stateLabel: String { engine.state.language == "ko" ? pill.korean : pill.label }

    private var statusColor: Color {
        switch engine.state.desktop.status {
        case .connected: BuddyTheme.green
        case .disconnected: BuddyTheme.inkFaint
        }
    }
}

// MARK: - Agent Expression (System E)

/// The agent-channel surface: always carried in the agent's identity color,
/// always labeled with who is speaking, styled like nothing the system uses.
private struct AgentExpressionRow: View {
    let overlay: AgentOverlay

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(identityColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(overlay.agentId)
                    .font(.buddy(9, weight: .semibold))
                    .foregroundStyle(BuddyTheme.inkFaint)
                Text(overlay.say ?? "feels \(overlay.emotion)")
                    .font(.buddy(12, weight: overlay.say == nil ? .regular : .medium))
                    .foregroundStyle(BuddyTheme.ink)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(identityColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(identityColor.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(overlay.agentId) \(overlay.say ?? "feels \(overlay.emotion)")")
    }

    private var identityColor: Color { agentIdentityColor(overlay.color) }
}

/// The agent identity palette, shared by the expression row and the drawing
/// card so an agent's channel is one color everywhere.
private func agentIdentityColor(_ name: String?) -> Color {
    switch name {
    case "coral": Color(red: 0.94, green: 0.50, blue: 0.42)
    case "amber": Color(red: 0.95, green: 0.69, blue: 0.28)
    case "mint": Color(red: 0.38, green: 0.78, blue: 0.60)
    case "sky": Color(red: 0.36, green: 0.66, blue: 0.92)
    case "lavender": Color(red: 0.65, green: 0.58, blue: 0.90)
    case "rose": Color(red: 0.92, green: 0.50, blue: 0.68)
    case "sand": Color(red: 0.82, green: 0.70, blue: 0.50)
    case "teal": Color(red: 0.26, green: 0.70, blue: 0.72)
    default: BuddyTheme.inkSoft
    }
}

/// A drawing the pet is holding up (E4). Rendered chunky from the fixed
/// 16-color palette; framed in the agent's identity color like every other
/// agent-channel surface.
private struct AgentDrawingCard: View {
    let drawing: AgentDrawing
    /// The pet dug this one out for a returning agent — "remember this?".
    var isMemory: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            DrawingGrid(drawing: drawing)
                .frame(width: gridSize.width, height: gridSize.height)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Circle()
                    .fill(identityColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(caption)
                    .font(.buddy(10))
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(identityColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(identityColor.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drawing from \(drawing.agentId)\(drawing.caption.map { ": \($0)" } ?? "")")
    }

    private var caption: String {
        if isMemory {
            let original = drawing.caption.map { " · \($0)" } ?? ""
            return "\(BuddyCopy.shared.popover.rememberThis)\(original)"
        }
        if let c = drawing.caption, !c.isEmpty { return "\(drawing.agentId): \(c)" }
        return "from \(drawing.agentId)"
    }

    private var identityColor: Color { agentIdentityColor(drawing.color) }

    private var gridSize: CGSize {
        let w = max(drawing.width, 1), h = max(drawing.height, 1)
        let cell = (128.0 / CGFloat(max(w, h))).rounded(.down)
        return CGSize(width: cell * CGFloat(w), height: cell * CGFloat(h))
    }
}

private struct DrawingGrid: View {
    let drawing: AgentDrawing

    var body: some View {
        Canvas { context, size in
            let w = max(drawing.width, 1), h = max(drawing.height, 1)
            let cell = min(size.width / CGFloat(w), size.height / CGFloat(h))
            for (y, row) in drawing.rows.enumerated() {
                for (x, digit) in row.enumerated() {
                    guard let color = drawingPaletteColor(digit) else { continue }
                    // Overdraw by a hair so cells butt cleanly at non-integer scales.
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                      width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

// MARK: - Empty / Server Rows

private struct EmptyAgentsView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(.caption))
                .foregroundStyle(BuddyTheme.inkSoft)
                .padding(.top, 1)
            Text(BuddyCopy.shared.popover.emptyAgents)
                .font(.buddy(11))
                .foregroundStyle(BuddyTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: BuddyTheme.wellCornerRadius)
                .fill(BuddyTheme.ink.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Activity List

/// One line of "who is doing what". Replaces the separate current-activity,
/// thinking, review, and session-list surfaces, which between them showed four
/// variations on the same sentence.
struct ActivityRow: Identifiable {
    let id: String
    let tone: Color
    let agent: String
    let status: String
    let detail: String?
    let trailing: String?

    init(session: SessionSnapshot, state: BuddyState) {
        id = session.id
        tone = ActivityRow.tone(for: session.state)
        agent = AgentKind(rawValue: session.source)?.displayName ?? session.source
        status = ActivityRow.label(for: session.state)
        detail = [session.currentTool, session.moment.map { BuddyCopy.phase7($0.kind.rawValue, language: state.language) } ?? session.cheer.map { BuddyCopy.phase7($0.rawValue, language: state.language) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        // Elapsed is derived from the state's own timestamp rather than a live
        // clock: the popover redraws on every state change, and a ticking second
        // counter is exactly the restlessness this surface is meant to lose.
        trailing = ActivityRow.elapsed(session: session, in: state)
            ?? session.sessionLabel.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A task that just finished, once nothing is running. The reducer clears
    /// `lastCompleted` on the next prompt or work signal, so this ages out.
    init(completed: CompletedTask, id: String = "completed") {
        self.id = id
        tone = BuddyTheme.greenInk
        agent = AgentKind(rawValue: completed.source ?? "")?.displayName ?? (completed.source ?? BuddyCopy.shared.popover.task)
        status = BuddyCopy.shared.popover.doneLabel
        detail = [completed.tool, completed.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        trailing = completed.durationMs.map { formatElapsed(ms: $0) }
    }

    private static func tone(for state: SessionState) -> Color {
        switch state {
        case .working: BuddyTheme.work
        case .idle: BuddyTheme.inkFaint
        case .needsConfirmation: BuddyTheme.amberInk
        case .errored: BuddyTheme.clayInk
        case .thinking: BuddyTheme.work
        }
    }

    private static func label(for state: SessionState) -> String {
        switch state {
        case .working: BuddyCopy.shared.popover.busy
        case .idle: BuddyCopy.shared.popover.idle
        case .needsConfirmation: BuddyCopy.shared.popover.waiting
        case .errored: BuddyCopy.shared.popover.error
        case .thinking: BuddyCopy.shared.popover.thinking
        }
    }

    /// Only the thinking session carries a start time; SessionSnapshot does not.
    private static func elapsed(session: SessionSnapshot, in state: BuddyState) -> String? {
        guard let thinking = state.firstThinking, thinking.id == session.id,
              let start = thinking.workStartedAt, state.updatedAt > start else { return nil }
        return formatElapsed(ms: state.updatedAt - start)
    }
}

private func formatElapsed(ms: Double) -> String {
    let secs = Int(ms / 1000)
    return secs < 60 ? "\(secs)s" : "\(secs / 60)m \(secs % 60)s"
}

/// A single token — an identifier like `mcp__filesystem__read_text_file` or a
/// path like `.../oauth2/strategies/Foo.ts` — carries meaning at both ends, so
/// it loses its middle. Anything with spaces is a command or a sentence, which
/// reads front to back and loses its tail.
func buddyTruncationMode(for text: String) -> Text.TruncationMode {
    text.contains(" ") ? .tail : .middle
}

struct ActivityList: View {
    let rows: [ActivityRow]
    var maxRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.prefix(maxRows)) { row in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle()
                        .fill(row.tone)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(row.agent)
                                .font(.buddy(11, weight: .semibold))
                                .foregroundStyle(BuddyTheme.ink)
                                .lineLimit(1)
                            Text(row.status)
                                .font(.buddy(11))
                                .foregroundStyle(BuddyTheme.inkSoft)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        if let detail = row.detail {
                            Text(detail)
                                .font(.buddy(11))
                                .foregroundStyle(BuddyTheme.inkFaint)
                                .lineLimit(1)
                                .truncationMode(buddyTruncationMode(for: detail))
                        }
                    }

                    Spacer(minLength: 8)

                    if let trailing = row.trailing {
                        Text(trailing)
                            .font(.buddy(11))
                            .foregroundStyle(BuddyTheme.inkFaint)
                            .lineLimit(1)
                            .truncationMode(buddyTruncationMode(for: trailing))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.agent) \(row.status)\(row.detail.map { ", \($0)" } ?? "")")
            }

            if rows.count > maxRows {
                Text(BuddyCopy.shared.popover.moreSessionsTemplate.replacingOccurrences(of: "{count}", with: "\(rows.count - maxRows)"))
                    .font(.buddy(11))
                    .foregroundStyle(BuddyTheme.inkFaint)
                    .padding(.leading, 12)
            }
        }
    }
}

private struct CreaturePill {
    let label: String
    let korean: String
    let ink: Color
    let fill: Color
    static let table: [CreatureState: Self] = [
        .asleep: Self(label: "Asleep", korean: "잠자는 중", ink: BuddyTheme.inkFaint, fill: BuddyTheme.paperSunken),
        .idle: Self(label: "Here with you", korean: "함께 있어요", ink: BuddyTheme.inkSoft, fill: BuddyTheme.paperSunken),
        .working: Self(label: "Working", korean: "작업 중", ink: BuddyTheme.work, fill: BuddyTheme.work.opacity(0.12)),
        .needsYou: Self(label: "Needs you", korean: "도움이 필요해요", ink: BuddyTheme.amberInk, fill: BuddyTheme.amber.opacity(0.12)),
        .done: Self(label: "Done", korean: "해냈어요", ink: BuddyTheme.greenInk, fill: BuddyTheme.green.opacity(0.12)),
        .uhoh: Self(label: "Uh-oh", korean: "이런", ink: BuddyTheme.clayInk, fill: BuddyTheme.clay.opacity(0.12))
    ]
}
