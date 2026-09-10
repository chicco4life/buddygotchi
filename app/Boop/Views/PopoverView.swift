import SwiftUI
import UniformTypeIdentifiers

enum ControlPane: String, CaseIterable { case overview, activity, settings, setup }
@Observable final class ControlNavigation {
    var pane: ControlPane = .overview
}

/// The shared control-center surface, also rendered by the snapshot harness.
struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    var serverHealth: ServerHealth? = nil
    var onUserInteraction: (() -> Void)? = nil
    var onOpenOnboarding: () -> Void = {}
    var onClose: () -> Void = {}
    var navigation: ControlNavigation = ControlNavigation()
    @State private var showingLeaderboard = false
    @State private var showingShelf = false
    @State private var history: [XPActivity] = []
    @State private var historyError = false
    private var growth: GrowthSnapshot { engine.state.growth }
    private func copy(_ en: String, _ ko: String) -> String { engine.state.language == "ko" ? ko : en }
    private func title(_ pane: ControlPane) -> String {
        switch pane {
        case .overview: copy("Overview", "개요")
        case .activity: copy("Activity", "활동")
        case .settings: copy("Settings", "설정")
        case .setup: copy("Set up Buddy", "Buddy 설정")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if navigation.pane != .overview {
                    Button { navigation.pane = .overview } label: {
                        Label(copy("Back", "뒤로"), systemImage: "chevron.left")
                    }.buttonStyle(.plain)
                }
                Text(navigation.pane == .overview ? engine.displayName : title(navigation.pane)).font(.headline)
                Spacer()
                if navigation.pane == .overview {
                    Text(copy("Level \(growth.level)", "레벨 \(growth.level)")).foregroundStyle(.secondary)
                }
            }.padding(18)
            if navigation.pane == .overview {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle).font(.headline)
                    Text(statusDetail).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.bottom, 14)
            }
            if navigation.pane == .overview, let card = engine.state.creature.card {
                if let prompt = engine.state.prompt, prompt.id == card.id {
                    Text([prompt.source.flatMap { AgentKind(rawValue: $0)?.displayName } ?? prompt.source, prompt.sessionLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 32)
                }
                NeedsYouCard(language: engine.state.language, card: card,
                    approve: { engine.resolveApproval(requestId: card.id, decision: .allow) },
                    deny: { engine.resolveApproval(requestId: card.id, decision: .deny) })
                    .padding(.horizontal, 18).padding(.bottom, 12)
            }
            switch navigation.pane {
            case .overview: ScrollView { overview.padding(.horizontal, 18).padding(.bottom, 12) }
            case .activity: ScrollView { activity.padding(18) }
            case .settings: settingsPane
            case .setup:
                OnboardingView(defaults: engine.preferences, engine: engine, esp32Output: esp32Output, compact: true) {
                    engine.refreshSettings()
                    navigation.pane = .overview
                }

            }
            Divider()
            HStack {
                if navigation.pane == .overview {
                    Button(copy("Activity", "활동")) { navigation.pane = .activity }
                    Spacer()
                    Button(copy("Settings", "설정")) { navigation.pane = .settings }
                } else { Spacer() }
                Menu {
                    Button(copy("Quit Boop", "Boop 종료")) { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }.buttonStyle(.plain).padding(14)
        }
        .frame(width: 360, height: navigation.pane == .overview ? overviewHeight : 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onClose)
        .onHover { if $0 { onUserInteraction?() } }
        .sheet(isPresented: $showingLeaderboard) { LeaderboardSheet(engine: engine) }
        .sheet(isPresented: $showingShelf) { KeepsakeShelfView(engine: engine, isPresented: $showingShelf) }
    }
    private var overviewHeight: CGFloat {
        // Grow for up to ten sessions; keep every row in the existing scroll view.
        let extraRows = max(0, min(engine.state.activeSessions.count, 10) - 3)
        let desired = CGFloat(engine.state.creature.card == nil ? 450 : 590) + CGFloat(extraRows) * 42
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        return min(desired, max(450, available))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !engine.boolSetting(DefaultsKey.setupCompleted) {
                Button(copy("Set up Buddy", "Buddy 설정")) { navigation.pane = .setup }.buttonStyle(.link)
            }
            Divider()
            HStack {
                Text(copy("Progress to level \(growth.level + 1)", "레벨 \(growth.level + 1)까지"))
                Spacer()
                Text("\(growth.xp - growth.levelStartXP) / \(growth.levelTargetXP - growth.levelStartXP) XP").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: growth.levelProgress).tint(.secondary)
            Text(copy("\(growth.xp.formatted()) total XP · \(max(0, growth.levelTargetXP - growth.xp)) to next level", "총 \(growth.xp.formatted()) XP · 다음 레벨까지 \(max(0, growth.levelTargetXP - growth.xp)) XP"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                metric(copy("XP today", "오늘 XP"), growth.today)
                Spacer()
                metric(copy("Tasks total", "총 작업"), growth.tasks)
                Spacer()
                metric(copy("Day streak", "연속 활동일"), growth.streak)
            }
            Divider()
            Text(copy("Sessions", "세션")).font(.caption).foregroundStyle(.secondary)
            if engine.state.activeSessions.isEmpty {
                Text(copy("No agents awake", "활성 에이전트 없음")).foregroundStyle(.secondary)
            } else {
                ActivityList(rows: engine.state.activeSessions.map { ActivityRow(session: $0, state: engine.state) }, maxRows: engine.state.activeSessions.count)
            }
            Divider()
            HStack {
                Text(copy("Device", "기기"))
                Spacer()
                Text(BuddyCopy.phase7("device-" + esp32Output.connectionState.rawValue, language: engine.state.language)).foregroundStyle(.secondary)
                if esp32Output.connectionState == .connected, let battery = engine.state.deviceBattery {
                    Text("\(battery.pct)%" + (battery.charging ? " ⚡" : "")).foregroundStyle(.secondary)
                }
            }.font(.callout)
        }
    }
    private var statusTitle: String {
        switch engine.state.creature.state {
        case .working: copy("Working", "작업 중")
        case .idle: copy("Idle", "대기 중")
        case .asleep: copy("Sleeping", "자는 중")
        case .needsYou: copy("Needs you", "확인 필요")
        case .done: copy("Done", "완료")
        case .uhoh: copy("Needs attention", "문제 확인 필요")
        }
    }
    private var statusDetail: String {
        switch engine.state.creature.state {
        case .working: copy("Your agents are making progress.", "에이전트가 작업 중입니다.")
        case .idle: copy("Ready when you are.", "준비되어 있습니다.")
        case .asleep: copy("No work in progress.", "진행 중인 작업이 없습니다.")
        case .needsYou: copy("An agent is waiting for your decision.", "에이전트가 결정을 기다립니다.")
        case .done: copy("Your agent finished its work.", "에이전트가 작업을 완료했습니다.")
        case .uhoh: copy("Open your agent to review the issue.", "에이전트에서 문제를 확인하세요.")
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !engine.state.activeSessions.isEmpty {
                ActivityList(rows: engine.state.activeSessions.map { ActivityRow(session: $0, state: engine.state) }, maxRows: engine.state.activeSessions.count)
                Divider()
            }
            Grid(alignment: .leading, horizontalSpacing: 44, verticalSpacing: 18) {
                GridRow { metric(copy("Tasks completed", "완료한 작업"), growth.tasks); metric(copy("Days together", "함께한 날"), growth.daysTogether) }
                GridRow { metric(copy("Current streak", "현재 연속 활동일"), growth.streak); metric(copy("Best streak", "최장 연속 활동일"), growth.bestStreak) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button(BuddyCopy.phase7("shareCard", language: engine.state.language)) { AppDelegate.presentShareCard(engine: engine) }
                Button(BuddyCopy.phase7("leaderboard", language: engine.state.language)) { showingLeaderboard = true }
                Menu(copy("More", "더 보기")) {
                    Button(BuddyCopy.phase7("recap", language: engine.state.language)) { Task { _ = try? await engine.makeRecap() } }
                    Button(BuddyCopy.shared.popover.keepsakeShelf) { showingShelf = true }
                }.fixedSize()
            }
            Divider()
            Text(copy("XP history", "XP 기록")).font(.headline)
            Text(copy("Recorded totals by day and source", "날짜와 유형별 기록된 합계")).font(.caption).foregroundStyle(.secondary)
            if historyError {
                Text(copy("Could not load XP history.", "XP 기록을 불러오지 못했습니다.")).foregroundStyle(.secondary)
                Button(copy("Retry", "다시 시도")) { Task { await loadHistory() } }
            } else if history.isEmpty {
                Text(copy("XP you earn will appear here.", "획득한 XP가 여기에 표시됩니다.")).foregroundStyle(.secondary)
            } else {
                ForEach(history) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sourceLabel(entry.source))
                            Text(entry.day).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(entry.xp) XP").monospacedDigit()
                    }
                    Divider()
                }
            }
            if engine.state.creature.card == nil {
                if engine.state.creature.gift {
                    Button(BuddyCopy.phase7("collect", language: engine.state.language)) { engine.collectArrived() }
                }
                if let bubble = engine.state.creature.bubble { Text(bubble).foregroundStyle(.secondary) }
                if let recap = engine.state.recap { RecapView(language: engine.state.language, recap: recap) }
                DisclosureGroup(copy("Agent messages", "에이전트 메시지")) {
                    if let overlay = engine.state.agentOverlay { AgentExpressionRow(overlay: overlay) }
                    if let drawing = engine.state.agentDrawing, engine.boolSetting(DefaultsKey.agentDrawingsEnabled, fallback: true) {
                        AgentDrawingCard(drawing: drawing, isMemory: engine.state.agentDrawingIsMemory == true)
                    }
                    if let tool = engine.teachTool {
                        Text(TeachCatalog.line(tool: tool, language: engine.state.language) ?? tool)
                        Button(BuddyCopy.phase7("quietTool", language: engine.state.language)) { Task { await engine.dismissTeach(tool: tool) } }
                    }
                }.font(.callout)
            }
        }.task(id: growth.xp) { await loadHistory() }
    }
    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted()).font(.title2.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func loadHistory() async {
        do { history = try await engine.recentXPActivity(); historyError = false }
        catch { historyError = true }
    }
    private func sourceLabel(_ source: XPSource) -> String {
        switch source {
        case .turn: copy("Completed turns", "완료한 턴")
        case .task: copy("Finished tasks", "완료한 작업")
        case .hardWonPass: copy("Hard-won passes", "노력 끝에 성공")
        case .activeDay: copy("Active day and streak", "활동일 및 연속 활동")
        case .streakBonus: copy("Streak bonus", "연속 활동 보너스")
        case .session: copy("Sessions started", "시작한 세션")
        case .checkIn: copy("Check-ins", "교감")
        case .tokens: copy("Output tokens", "출력 토큰")
        }
    }
    private var settingsPane: some View {
        SettingsSectionView(isPresented: .constant(true), engine: engine, esp32Output: esp32Output,
            serverHealth: serverHealth, onOpenOnboarding: onOpenOnboarding, section: .all)
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
    let project: String?
    let status: String
    let detail: String?
    let trailing: String?

    init(session: SessionSnapshot, state: BuddyState) {
        id = session.id
        tone = ActivityRow.tone(for: session.state)
        project = session.sessionLabel
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
        project = nil
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.agent).lineLimit(1)
                        if let project = row.project, !project.isEmpty {
                            Text(project).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(row.status).foregroundStyle(.secondary)
                }.font(.callout).accessibilityElement(children: .combine)
            }
        }
    }
}
