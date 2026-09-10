import SwiftUI
import UniformTypeIdentifiers

enum ControlPane: String, CaseIterable { case overview, settings, setup }
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
            HStack {
                if navigation.pane != .overview {
                    Button { navigation.pane = .overview } label: {
                        Label(copy("Back", "뒤로"), systemImage: "chevron.left")
                    }.buttonStyle(.plain)
                }
                Text(navigation.pane == .overview ? engine.displayName : title(navigation.pane)).font(.headline)
                Spacer()
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
                NeedsYouCard(language: engine.state.language, card: card)
                    .padding(.horizontal, 18).padding(.bottom, 8)
                Button(copy("Snooze reminder", "알림 잠시 끄기")) { engine.nudgeDismissed(requestId: card.id) }
                    .buttonStyle(.link).font(.caption).padding(.horizontal, 32).padding(.bottom, 12)
            }
            switch navigation.pane {
            case .overview: ScrollView { overview.padding(.horizontal, 18).padding(.bottom, 12) }
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
                    Button(copy("Settings", "설정")) { navigation.pane = .settings }
                }
                Spacer()
                Button(copy("Quit", "종료")) { NSApp.terminate(nil) }
            }.buttonStyle(.plain).padding(14)
        }
        .frame(width: 360, height: navigation.pane == .overview ? overviewHeight : 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onClose)
        .onHover { if $0 { onUserInteraction?() } }
    }
    private var overviewHeight: CGFloat {
        // Grow for up to ten sessions; keep every row in the existing scroll view.
        let extraRows = max(0, min(engine.state.activeSessions.count, 10) - 1)
        let desired = CGFloat(engine.state.creature.card == nil ? 440 : 580) + CGFloat(extraRows) * 42
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        return min(desired, max(440, available))
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !engine.boolSetting(DefaultsKey.setupCompleted) {
                Button(copy("Set up Buddy", "Buddy 설정")) { navigation.pane = .setup }.buttonStyle(.link)
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
            Divider()
            xpSection
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(growth.xp.formatted()) XP").fontWeight(.medium)
                Spacer()
                Text(copy("\(growth.tasks.formatted()) turns", "\(growth.tasks.formatted())턴"))
                Spacer()
                Text(copy("\(growth.streak)-day streak", "\(growth.streak)일 연속"))
            }.font(.caption)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                DailyActivityGrid(activity: activityDays, date: context.date, language: engine.state.language)
                    .task(id: "\(growth.xp)-\(CivilDay.localDay(at: context.date.timeIntervalSince1970 * 1000, calendar: .current))") {
                        do { activityDays = try await engine.dailyActivity(); activityError = false }
                        catch { activityError = true }
                    }
            }
            if activityError {
                Text(copy("Activity history unavailable", "활동 기록을 불러올 수 없습니다"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private var settingsPane: some View {
        SettingsSectionView(isPresented: .constant(true), engine: engine, esp32Output: esp32Output,
            serverHealth: serverHealth, onOpenOnboarding: onOpenOnboarding, section: .all)
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
