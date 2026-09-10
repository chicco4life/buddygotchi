import SwiftUI
import UniformTypeIdentifiers

enum ControlPane: String, CaseIterable { case overview, activity, settings }
@Observable final class ControlNavigation {
    var pane: ControlPane = .overview
    var settingsCategory: SettingsSection = .device
}

/// The shared control-center surface, also rendered by the snapshot harness.
struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    var serverHealth: ServerHealth? = nil
    var onUserInteraction: (() -> Void)? = nil
    var onOpenOnboarding: () -> Void = {}
    var navigation: ControlNavigation = ControlNavigation()
    private var settings: SettingsSection {
        get { navigation.settingsCategory }
        nonmutating set { navigation.settingsCategory = newValue }
    }
    @State private var showingLeaderboard = false
    @State private var showingShelf = false
    @State private var history: [XPActivity] = []
    @State private var historyError = false
    @State private var appearanceError = false
    private var growth: GrowthSnapshot { engine.state.growth }
    private func copy(_ en: String, _ ko: String) -> String { engine.state.language == "ko" ? ko : en }
    private func title(_ pane: ControlPane) -> String {
        switch pane {
        case .overview: copy("Overview", "개요")
        case .activity: copy("Activity", "활동")
        case .settings: copy("Settings", "설정")
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(BuddyCopy.shared.common.appName).font(.title2.weight(.semibold)).padding(.bottom, 24)
                ForEach(ControlPane.allCases, id: \.self) { pane in
                    Button { navigation.pane = pane } label: {
                        Label(title(pane), systemImage: pane == .overview ? "square.grid.2x2" : pane == .activity ? "clock" : "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(navigation.pane == pane ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.pane == pane ? .isSelected : [])
                }
                Spacer()
                Text(engine.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(copy("Device companion", "기기 제어 센터")).font(.caption2).foregroundStyle(.tertiary)
            }.padding(18).frame(width: 170).background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title(navigation.pane)).font(.title2.weight(.semibold))
                    Spacer()
                    if navigation.pane == .overview {
                        Toggle(BuddyCopy.phase7("focus", language: engine.state.language), isOn: Binding(
                            get: { engine.state.creature.focus }, set: { engine.focusToggled(on: $0) }))
                            .toggleStyle(.switch).controlSize(.small).fixedSize()
                    }
                }.padding(24)
                if let card = engine.state.creature.card {
                    NeedsYouCard(language: engine.state.language, card: card,
                        approve: { engine.resolveApproval(requestId: card.id, decision: .allow) },
                        deny: { engine.resolveApproval(requestId: card.id, decision: .deny) })
                        .padding(.horizontal, 24).padding(.bottom, 12)
                }
                if !engine.boolSetting(DefaultsKey.setupCompleted) {
                    HStack {
                        Text(copy("Finish connecting your Buddy.", "Buddy 연결을 완료하세요."))
                        Spacer()
                        Button(copy("Set up", "설정 시작"), action: onOpenOnboarding)
                    }.padding(.horizontal, 24).padding(.bottom, 12)
                }
                switch navigation.pane {
                case .overview: ScrollView { overview.padding(24).padding(.top, -12) }
                case .activity: ScrollView { activity.padding(24).padding(.top, -12) }
                case .settings: settingsPane
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 760, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onHover { if $0 { onUserInteraction?() } }
        .sheet(isPresented: $showingLeaderboard) { LeaderboardSheet(engine: engine) }
        .sheet(isPresented: $showingShelf) { KeepsakeShelfView(engine: engine, isPresented: $showingShelf) }
        .alert(copy("Could not change appearance", "외형을 변경하지 못했습니다"), isPresented: $appearanceError) {
            Button(copy("OK", "확인")) {}
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(copy("Level \(growth.level)", "레벨 \(growth.level)")).font(.system(size: 32, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(growth.xp.formatted()) XP").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: growth.levelProgress).tint(.accentColor)
                HStack {
                    Text(copy("+\(growth.today) XP today", "오늘 +\(growth.today) XP"))
                    Spacer()
                    Text(copy("\(max(0, growth.levelTargetXP - growth.xp)) to Level \(growth.level + 1)", "레벨 \(growth.level + 1)까지 \(max(0, growth.levelTargetXP - growth.xp)) XP"))
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(20).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("Device", "기기")).font(.headline)
                HStack {
                    Text(engine.displayName)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(esp32Output.connectionState == .connected ? Color.green : .secondary).frame(width: 6, height: 6)
                        Text(BuddyCopy.phase7("device-" + esp32Output.connectionState.rawValue, language: engine.state.language))
                    }
                }
                if esp32Output.connectionState == .connected, let battery = engine.state.deviceBattery {
                    HStack { Text(copy("Battery", "배터리")); Spacer(); Text("\(battery.pct)%" + (battery.charging ? copy(" · Charging", " · 충전 중") : "")).foregroundStyle(.secondary) }
                } else {
                    HStack { Text(copy("Battery", "배터리")); Spacer(); Text(copy("Unavailable", "확인할 수 없음")).foregroundStyle(.secondary) }
                }
                Button(copy("Manage device", "기기 관리")) { settings = .device; navigation.pane = .settings }
                    .buttonStyle(.link)
            }.font(.callout)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("Agents", "에이전트")).font(.headline)
                if engine.state.activeSessions.isEmpty {
                    Text(copy("No active sessions", "활성 세션 없음")).foregroundStyle(.secondary)
                } else {
                    ActivityList(rows: engine.state.activeSessions.map { ActivityRow(session: $0, state: engine.state) }, maxRows: engine.state.activeSessions.count)
                }
                Button(copy("View activity", "활동 보기")) { navigation.pane = .activity }.buttonStyle(.link)
            }
        }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 20) {
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
        VStack(spacing: 0) {
            Picker(copy("Category", "카테고리"), selection: Binding(get: { settings }, set: { settings = $0 })) {
                Text(copy("Device", "기기")).tag(SettingsSection.device)
                Text(copy("Agents", "에이전트")).tag(SettingsSection.agents)
                Text(copy("Appearance", "외형")).tag(SettingsSection.displays)
                Text(copy("General", "일반")).tag(SettingsSection.buddy)
                Text(copy("Focus", "집중")).tag(SettingsSection.focus)
                Text(copy("Advanced", "고급")).tag(SettingsSection.advanced)
            }.pickerStyle(.menu).padding(.horizontal, 24).padding(.bottom, 8)
            if settings == .displays {
                Form {
                    Section {
                        cosmeticPicker("skin", label: copy("Color", "색상"))
                        cosmeticPicker("accessory", label: copy("Accessory", "액세서리"))
                        cosmeticPicker("silhouette", label: copy("Silhouette", "실루엣"))
                    } footer: { Text(copy("All appearances are available. XP unlocks nothing.", "모든 외형을 사용할 수 있습니다. XP는 잠금 해제에 사용되지 않습니다.")) }
                }.formStyle(.grouped)
            } else {
                SettingsSectionView(isPresented: .constant(true), engine: engine, esp32Output: esp32Output,
                    serverHealth: serverHealth, onOpenOnboarding: onOpenOnboarding, section: settings).id(settings)
            }
        }
    }
    private func cosmeticPicker(_ kind: String, label: String) -> some View {
        Picker(label, selection: Binding(get: {
            switch kind { case "skin": engine.state.cosmetic.skin; case "accessory": engine.state.cosmetic.accessory; default: engine.state.cosmetic.silhouette }
        }, set: { value in
            var selected = engine.state.cosmetic
            switch kind { case "skin": selected.skin = value; case "accessory": selected.accessory = value; default: selected.silhouette = value }
            Task { do { try await engine.equip(selected) } catch { appearanceError = true } }
        })) {
            ForEach(CompanionOption.catalog.filter { $0.kind == kind }, id: \.name) { Text($0.name.capitalized).tag($0.name) }
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
