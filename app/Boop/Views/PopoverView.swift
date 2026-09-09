import SwiftUI
import UniformTypeIdentifiers

struct PopoverView: View {
    @State private var showingLeaderboard = false
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
            Rectangle().fill(.regularMaterial).ignoresSafeArea()

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
                    .font(.headline)
                    .foregroundStyle(BuddyTheme.ink)
                    .multilineTextAlignment(.center)
                Text(BuddyCopy.Onboarding.finishMeetingSubtitle)
                    .font(.footnote)
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Button(BuddyCopy.Onboarding.meetBuddy, action: onOpenOnboarding)
                .buttonStyle(.borderedProminent).tint(BuddyTheme.amber)

            Spacer()
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth, height: BuddyTheme.unfinishedSetupHeight)

    }

    // MARK: - Live View

    private var liveView: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            CreatureView(creature: engine.state.creature, cosmetic: engine.state.cosmetic, paused: !engine.popoverVisible)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            if let card = engine.state.creature.card {
                NeedsYouCard(language: engine.state.language, card: card,
                    approve: { engine.resolveApproval(requestId: card.id, decision: .allow) },
                    deny: { engine.resolveApproval(requestId: card.id, decision: .deny) })
            }
            let rows = engine.state.activeSessions.map { ActivityRow(session: $0, state: engine.state) }
            if rows.count > 1 {
                ScrollView { ActivityList(rows: rows, maxRows: rows.count) }
                    .frame(height: min(CGFloat(rows.count) * 26, 104))
            } else if rows.isEmpty {
                Text(BuddyCopy.phase7("noAgentsAwake", language: engine.state.language))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if engine.state.creature.card == nil {
                if engine.state.creature.gift {
                    Button { engine.collectArrived() } label: {
                        HStack {
                            Circle().fill(BuddyTheme.amber.gradient).frame(width: 18, height: 18)
                            Text(engine.state.creature.giftLine ?? BuddyCopy.phase7("collect", language: engine.state.language))
                                .font(.body).foregroundStyle(.primary)
                        }
                    }.buttonStyle(.plain)
                } else if let bubble = engine.state.creature.bubble {
                    Text(bubble).font(.body)
                }
                if let tool = engine.teachTool {
                    HStack {
                        Text(TeachCatalog.line(tool: tool, language: engine.state.language) ?? tool).font(.footnote)
                        Button { Task { await engine.dismissTeach(tool: tool) } } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(BuddyCopy.phase7("quietTool", language: engine.state.language))
                    }.foregroundStyle(.secondary)
                }
                if let overlay = engine.state.agentOverlay { AgentExpressionRow(overlay: overlay) }
                if let drawing = engine.state.agentDrawing, agentDrawingsEnabled {
                    AgentDrawingCard(drawing: drawing, isMemory: engine.state.agentDrawingIsMemory == true)
                }
                if let recap = engine.state.recap, engine.state.prompt == nil {
                    RecapView(language: engine.state.language, recap: recap)
                }
            }
            if showMenuHint {
                Text(BuddyCopy.Onboarding.menuHint).font(.caption).foregroundStyle(.secondary)
                    .task { try? await Task.sleep(for: .seconds(4)); showMenuHint = false }
            }
            footerRow
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth)
        .frame(minHeight: BuddyTheme.liveViewHeight, alignment: .top)
        .animation(reduceMotion ? nil : .buddyBloom(), value: engine.state.prompt != nil)
        .sheet(isPresented: $showingLeaderboard) { LeaderboardSheet(engine: engine) }
    }

    private var headerRow: some View {
        HStack {
            Text(engine.displayName).font(.headline).lineLimit(1)
            Text(BuddyCopy.phase7(engine.state.creature.state.rawValue, language: engine.state.language))
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Menu {
                Button(BuddyCopy.book(language: engine.state.language).common.settings) {
                    CompanionWindows.shared.settings(engine: engine, device: esp32Output, onOnboarding: onOpenOnboarding)
                }
                Button(BuddyCopy.phase7("shareCard", language: engine.state.language)) { AppDelegate.presentShareCard(engine: engine) }
                Button(BuddyCopy.phase7("leaderboard", language: engine.state.language)) { showingLeaderboard = true }
                Button(BuddyCopy.phase7("recap", language: engine.state.language)) { Task { _ = try? await engine.makeRecap() } }
                if !engine.petMemory.keepsakes.isEmpty {
                    Button(BuddyCopy.shared.popover.keepsakeShelf) { showingShelf = true }
                }
            } label: { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(BuddyCopy.book(language: engine.state.language).common.settings)
        }
    }

    private var footerRow: some View {
        HStack {
            Text(BuddyCopy.growthLabel(engine.state.growth, language: engine.state.language))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Toggle(BuddyCopy.phase7("focus", language: engine.state.language), isOn: Binding(
                get: { engine.state.creature.focus }, set: { engine.focusToggled(on: $0) }))
                .toggleStyle(.button).buttonStyle(.bordered).controlSize(.small)
            if engine.pairedPeripheral != nil {
                Circle().fill(esp32Output.connectionState == .connected ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(BuddyCopy.phase7("device-" + esp32Output.connectionState.rawValue, language: engine.state.language))
            }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BuddyTheme.inkFaint)
                Text(overlay.say ?? "feels \(overlay.emotion)")
                    .font(.callout.weight(overlay.say == nil ? .regular : .medium))
                    .foregroundStyle(BuddyTheme.ink)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
                    .font(.caption)
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
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
        status = ActivityRow.label(for: session.state, language: state.language)
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

    private static func label(for state: SessionState, language: String) -> String {
        switch state {
        case .working: BuddyCopy.phase7("working", language: language)
        case .idle: BuddyCopy.phase7("idle", language: language)
        case .needsConfirmation: BuddyCopy.phase7("needsYou", language: language)
        case .errored: BuddyCopy.phase7("uhoh", language: language)
        case .thinking: BuddyCopy.phase7("working", language: language)
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
                HStack(spacing: 6) {
                    Image(systemName: "terminal").foregroundStyle(.secondary)
                    Text(row.agent).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.status).foregroundStyle(.secondary)
                }.font(.callout).accessibilityElement(children: .combine)
            }
        }
    }
}
