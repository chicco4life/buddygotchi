import SwiftUI
import UniformTypeIdentifiers

enum ControlPane: String, CaseIterable { case overview, settings, setup }
@Observable final class ControlNavigation {
    var pane: ControlPane = .overview
}

/// The shared control-center surface, also rendered by the snapshot harness.
///
/// The column is a stack of one object: a labelled section, then a card. There
/// are no horizontal rules between sections — space and the small section label
/// do that work, which keeps a 360 pt column from reading as a form.
struct PopoverView: View {
    let engine: BuddyEngine
    let esp32Output: ESP32Output
    var serverHealth: ServerHealth? = nil
    var onUserInteraction: (() -> Void)? = nil
    var onOpenOnboarding: () -> Void = {}
    var onClose: () -> Void = {}
    var navigation: ControlNavigation = ControlNavigation()
    @State private var activityDays: [DailyActivity] = []
    @State private var activityError = false
    private var growth: GrowthSnapshot { engine.state.growth }
    private func copy(_ en: String, _ ko: String) -> String { engine.state.language == "ko" ? ko : en }
    private func title(_ pane: ControlPane) -> String {
        switch pane {
        case .overview: copy("Overview", "개요")
        case .settings: copy("Settings", "설정")
        case .setup: copy("Set up Buddy", "Buddy 설정")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if navigation.pane == .overview { statusBlock }
            if navigation.pane == .overview, let card = engine.state.creature.card { needsYou(card) }
            switch navigation.pane {
            case .overview:
                ScrollView {
                    overview
                        .padding(.horizontal, BuddyTheme.gutter)
                        .padding(.bottom, BuddyTheme.gap)
                }
            case .settings: settingsPane
            case .setup:
                OnboardingView(defaults: engine.preferences, engine: engine, esp32Output: esp32Output, compact: true) {
                    engine.refreshSettings()
                    navigation.pane = .overview
                }
            }
            footer
        }
        .frame(width: BuddyTheme.popoverWidth, height: navigation.pane == .overview ? overviewHeight : 560)
        .background(BuddyTheme.paper)
        .foregroundStyle(BuddyTheme.ink)
        .onExitCommand(perform: onClose)
        .onHover { if $0 { onUserInteraction?() } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BuddyTheme.gapSnug) {
            if navigation.pane != .overview {
                Button { withAnimation(.buddySettle()) { navigation.pane = .overview } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.buddyText)
                .accessibilityLabel(copy("Back", "뒤로"))
            }
            Text(navigation.pane == .overview ? engine.displayName : title(navigation.pane))
                .font(.system(size: 16, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, navigation.pane == .overview ? BuddyTheme.gutter : BuddyTheme.gutter - 8)
        .padding(.top, BuddyTheme.gutter)
        .padding(.bottom, navigation.pane == .overview ? BuddyTheme.gap : BuddyTheme.gapLoose)
    }

    /// Tone dot, state, and one plain sentence. The dot is the only place a
    /// colour carries meaning on its own, so it repeats the word beside it.
    private var statusBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: BuddyTheme.gapSnug) {
            BuddyStateDot(tone: statusTone, pulsing: statusIsLive)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle).font(.system(size: 13, weight: .semibold))
                if let scope = engine.state.workScope, engine.state.prompt == nil {
                    Text(scope)
                        .font(.system(size: 12))
                        .foregroundStyle(BuddyTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(BuddyTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BuddyTheme.gutter)
        .padding(.bottom, BuddyTheme.gapLoose)
        .animation(.buddySettle(), value: engine.state.creature.state)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func needsYou(_ card: CreatureCard) -> some View {
        VStack(alignment: .leading, spacing: BuddyTheme.gapTight) {
            if let prompt = engine.state.prompt, prompt.id == card.id {
                Text([prompt.source.flatMap { AgentKind(rawValue: $0)?.displayName } ?? prompt.source, prompt.sessionLabel]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BuddyTheme.amberInk)
            }
            NeedsYouCard(language: engine.state.language, card: card)
            Button(copy("Snooze reminder", "알림 잠시 끄기")) { engine.nudgeDismissed(requestId: card.id) }
                .buttonStyle(.buddyText)
                .font(.system(size: 11))
                .padding(.leading, -8)
        }
        .padding(.horizontal, BuddyTheme.gutter)
        .padding(.bottom, BuddyTheme.gapLoose)
        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                                removal: .opacity))
        .animation(.buddyPop(), value: card.id)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            BuddyDivider()
            HStack {
                if navigation.pane == .overview {
                    Button(copy("Settings", "설정")) { withAnimation(.buddySettle()) { navigation.pane = .settings } }
                }
                Spacer()
                Button(copy("Quit", "종료")) { NSApp.terminate(nil) }
            }
            .font(.system(size: 12))
            .buttonStyle(.buddyText)
            .padding(.horizontal, BuddyTheme.gutter - 8)
            .padding(.vertical, BuddyTheme.gapSnug)
        }
    }

    private var overviewHeight: CGFloat {
        // Grow for up to ten sessions; keep every row in the existing scroll view.
        let extraRows = max(0, min(engine.state.activeSessions.count, 10) - 1)
        let desired = CGFloat(engine.state.creature.card == nil ? 548 : 692) + CGFloat(extraRows) * 46
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        return min(desired, max(548, available))
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: BuddyTheme.gapSection) {
            if !engine.boolSetting(DefaultsKey.setupCompleted) {
                BuddyCard(tone: BuddyTheme.accent) {
                    HStack(spacing: BuddyTheme.gapSnug) {
                        Image(systemName: "sparkles").foregroundStyle(BuddyTheme.accentInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copy("Finish setting up Buddy", "Buddy 설정을 마치세요"))
                                .font(.system(size: 12, weight: .medium))
                            Text(copy("Connect your agents and device.", "에이전트와 기기를 연결하세요."))
                                .font(.system(size: 11)).foregroundStyle(BuddyTheme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BuddyTheme.inkFaint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.buddySettle()) { navigation.pane = .setup } }
            }
            section(copy("Sessions", "세션")) {
                if engine.state.activeSessions.isEmpty {
                    BuddyCard {
                        HStack(spacing: BuddyTheme.gapSnug) {
                            Image(systemName: "moon.zzz").font(.system(size: 12))
                                .foregroundStyle(BuddyTheme.inkFaint)
                            Text(copy("No agents awake", "활성 에이전트 없음"))
                                .font(.system(size: 12)).foregroundStyle(BuddyTheme.inkSoft)
                            Spacer(minLength: 0)
                        }
                    }
                } else {
                    ActivityList(rows: engine.state.activeSessions.map { ActivityRow(session: $0, state: engine.state) },
                                 maxRows: engine.state.activeSessions.count)
                }
            }
            section(copy("Device", "기기")) { deviceCard }
            section(copy("Progress", "진행")) { xpSection }
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BuddyTheme.gapSnug) {
            BuddySectionLabel(text: label)
            content()
        }
    }

    private var deviceConnected: Bool { esp32Output.connectionState == .connected }

    private var deviceCard: some View {
        BuddyCard {
            HStack(spacing: BuddyTheme.gapSnug) {
                Image(systemName: deviceConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(deviceConnected ? BuddyTheme.greenInk : BuddyTheme.inkFaint)
                    .frame(width: 16)
                Text(BuddyCopy.phase7("device-" + esp32Output.connectionState.rawValue, language: engine.state.language))
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                if deviceConnected, let battery = engine.state.deviceBattery {
                    BatteryPip(percent: battery.pct, charging: battery.charging)
                }
            }
        }
        .animation(.buddySettle(), value: esp32Output.connectionState)
    }

    private var statusTone: Color {
        switch engine.state.creature.state {
        case .working: BuddyTheme.accentInk
        case .idle: BuddyTheme.inkFaint
        case .asleep: BuddyTheme.inkFaint
        case .needsYou: BuddyTheme.amber
        case .done: BuddyTheme.green
        case .uhoh: BuddyTheme.clay
        }
    }

    /// Only live work breathes. Idle, asleep and resolved states hold still.
    private var statusIsLive: Bool {
        switch engine.state.creature.state {
        case .working, .needsYou: true
        default: false
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
        case .needsYou: copy("An agent needs your attention in the editor.", "에디터에서 에이전트의 요청을 확인해 주세요.")
        case .done: copy("Your agent finished its work.", "에이전트가 작업을 완료했습니다.")
        case .uhoh: copy("Open your agent to review the issue.", "에이전트에서 문제를 확인하세요.")
        }
    }

    private var xpSection: some View {
        VStack(alignment: .leading, spacing: BuddyTheme.gap) {
            HStack(spacing: BuddyTheme.gapSnug) {
                StatTile(value: growth.xp.formatted(), label: copy("XP", "XP"), tone: BuddyTheme.accentInk)
                StatTile(value: growth.tasks.formatted(), label: copy("turns", "턴"), tone: BuddyTheme.ink)
                StatTile(value: "\(growth.streak)", label: copy("day streak", "일 연속"),
                         tone: growth.streak > 0 ? BuddyTheme.amberInk : BuddyTheme.inkFaint)
            }
            VStack(alignment: .leading, spacing: BuddyTheme.gapSnug) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    DailyActivityGrid(activity: activityDays, date: context.date, language: engine.state.language)
                        .task(id: "\(growth.xp)-\(CivilDay.localDay(at: context.date.timeIntervalSince1970 * 1000, calendar: .current))") {
                            do { activityDays = try await engine.dailyActivity(); activityError = false }
                            catch { activityError = true }
                        }
                }
                if activityError {
                    Text(copy("Activity history unavailable", "활동 기록을 불러올 수 없습니다"))
                        .font(.system(size: 10)).foregroundStyle(BuddyTheme.inkFaint)
                }
            }
        }
    }
    private var settingsPane: some View {
        SettingsSectionView(isPresented: .constant(true), engine: engine, esp32Output: esp32Output,
            serverHealth: serverHealth, onOpenOnboarding: onOpenOnboarding, section: .all)
    }
}

// MARK: - Small parts

/// One number and its unit. Three of these sit in a row; the number is the
/// only thing sized up, so the row scans as three values rather than six words.
struct StatTile: View {
    let value: String
    let label: String
    var tone: Color = BuddyTheme.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tone)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(BuddyTheme.inkFaint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(BuddyTheme.raised, in: RoundedRectangle(cornerRadius: BuddyTheme.wellCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BuddyTheme.wellCornerRadius)
                .strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
        )
        .animation(.buddySettle(), value: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// A real little battery rather than a percentage string. It fills from the
/// left and takes the amber tone under 25%, matching the device's low-battery mark.
struct BatteryPip: View {
    let percent: Int
    let charging: Bool
    private var tone: Color { percent < 25 && !charging ? BuddyTheme.amberInk : BuddyTheme.inkSoft }
    var body: some View {
        HStack(spacing: 5) {
            if charging {
                Image(systemName: "bolt.fill").font(.system(size: 8))
                    .foregroundStyle(BuddyTheme.greenInk)
            }
            Text("\(percent)%").font(.system(size: 11, weight: .medium)).foregroundStyle(tone)
                .contentTransition(.numericText())
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).strokeBorder(BuddyTheme.hairlineStrong, lineWidth: 1)
                    .frame(width: 20, height: 10)
                RoundedRectangle(cornerRadius: 1)
                    .fill(tone)
                    .frame(width: max(1, 16 * CGFloat(min(max(percent, 0), 100)) / 100), height: 6)
                    .padding(.leading, 2)
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(BuddyTheme.hairlineStrong)
                    .frame(width: 1.5, height: 4)
                    .offset(x: 2)
            }
        }
        .animation(.buddySettle(), value: percent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent)%")
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
    let project: String?
    let status: String
    let detail: String?
    let trailing: String?
    let symbol: String
    let live: Bool

    init(session: SessionSnapshot, state: BuddyState) {
        id = session.id
        tone = ActivityRow.tone(for: session.state)
        project = session.sessionLabel
        agent = AgentKind(rawValue: session.source)?.displayName ?? session.source
        symbol = ActivityRow.symbol(for: session.source)
        status = ActivityRow.label(for: session.state, language: state.language)
        live = session.state == .working || session.state == .thinking
        detail = [session.currentTool, session.cheer.map { BuddyCopy.phase7($0.rawValue, language: state.language) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        trailing = session.sessionLabel.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A task that just finished, once nothing is running. The reducer clears
    /// `lastCompleted` on the next prompt or work signal, so this ages out.
    init(completed: CompletedTask, id: String = "completed") {
        self.id = id
        project = nil
        tone = BuddyTheme.greenInk
        agent = AgentKind(rawValue: completed.source ?? "")?.displayName ?? (completed.source ?? BuddyCopy.shared.popover.task)
        symbol = ActivityRow.symbol(for: completed.source ?? "")
        status = BuddyCopy.shared.popover.doneLabel
        live = false
        detail = [completed.tool, completed.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        trailing = completed.durationMs.map { formatElapsed(ms: $0) }
    }

    private static func tone(for state: SessionState) -> Color {
        switch state {
        case .working: BuddyTheme.accentInk
        case .idle: BuddyTheme.inkFaint
        case .needsConfirmation: BuddyTheme.amberInk
        case .errored: BuddyTheme.clayInk
        case .thinking: BuddyTheme.accentInk
        }
    }

    /// Each agent gets its own glyph so a row is identifiable before it is read.
    private static func symbol(for source: String) -> String {
        switch AgentKind(rawValue: source) {
        case .claudeCode: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .codex: "curlybraces"
        case .none: "terminal"
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
        VStack(spacing: BuddyTheme.gapTight + 2) {
            ForEach(rows.prefix(maxRows)) { row in
                SessionRow(row: row)
                    .transition(.asymmetric(insertion: .scale(scale: 0.97, anchor: .leading).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .animation(.buddyPop(), value: rows.map(\.id))
    }
}

/// A session card. The tone lives in a 3 pt bar down the leading edge rather
/// than in the text, so ten rows do not turn into ten coloured sentences.
struct SessionRow: View {
    let row: ActivityRow
    var body: some View {
        HStack(spacing: BuddyTheme.gapSnug) {
            Image(systemName: row.symbol)
                .font(.system(size: 11))
                .foregroundStyle(BuddyTheme.inkFaint)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.agent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let project = row.project, !project.isEmpty {
                    Text(project)
                        .font(.system(size: 10)).foregroundStyle(BuddyTheme.inkSoft)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: BuddyTheme.gapTight)
            StatusChip(text: row.status, tone: row.tone, live: row.live)
        }
        .padding(.leading, 13).padding(.trailing, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BuddyTheme.raised, in: RoundedRectangle(cornerRadius: BuddyTheme.wellCornerRadius))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: BuddyTheme.accentBarRadius)
                .fill(row.tone)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: BuddyTheme.wellCornerRadius)
                .strokeBorder(BuddyTheme.hairline, lineWidth: BuddyTheme.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
    }
}

/// The state word, set in its own tone on a wash of the same hue. Working
/// carries a slow breath so a long-running session looks alive at a glance.
struct StatusChip: View {
    let text: String
    let tone: Color
    var live = false
    @State private var breathing = false
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tone.opacity(0.12), in: RoundedRectangle(cornerRadius: BuddyTheme.chipCornerRadius))
            .opacity(live && breathing ? 0.62 : 1)
            .animation(live ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .buddySettle(),
                       value: breathing)
            .onAppear { breathing = live }
            .onChange(of: live) { _, value in breathing = value }
    }
}
