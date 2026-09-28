import BoopKit
import SwiftUI

/// Overview, top to bottom: Boop and how things are, who needs you, and
/// every session by agent. Controls live in Settings.
struct OverviewPane: View {
    @ObservedObject var model: AppModel
    var maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            FittedScroll(maxHeight: maxHeight - 76) {
                VStack(alignment: .leading, spacing: Theme.gapSection) {
                    if let error = model.startError {
                        notice("exclamationmark.triangle.fill", Theme.clayInk, "Boop couldn't start", error)
                    }
                    if let trouble = model.status?.brainTrouble {
                        notice("exclamationmark.triangle.fill", Theme.clayInk, "Jev isn't answering",
                               Self.brainProblem(trouble))
                    }
                    if model.restartAgents {
                        notice("arrow.clockwise", Theme.inkSoft, "Restart your agent sessions",
                               "Open sessions pick up Boop's hooks when they restart.") {
                            model.restartAgents = false
                        }
                    }
                    if let status = model.status {
                        if let attn = status.snapshot.attn { needsYou(attn, status.sessions) }
                        PaneSection(status.sessions.isEmpty ? "Sessions" : "Sessions · \(status.sessions.count)") {
                            sessions(status)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, Theme.gapLoose)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.gapSnug) {
            HStack(spacing: Theme.gap) {
                HStack(spacing: Theme.gap) {
                    BoopFace(mood: FaceMood(model.status), design: model.status?.snapshot.mood ?? MoodAction.initial,
                             size: faceSize)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.gap) {
                            // A long name shrinks a little before it's cut.
                            Text(model.name).font(.boop(18)).lineLimit(1).minimumScaleFactor(0.8)
                                .layoutPriority(1)
                            if let mood = model.status?.snapshot.mood { moodLabel(mood) }
                        }
                        HStack(spacing: 6) {
                            StateDot(tone: tone, pulsing: live)
                            Text(headline).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        }
                        .animation(.boopSettle, value: headline)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if model.status != nil {
                    DeviceLine(model: model)
                }
            }
            // Under the name, the full width of the popover, so the chips
            // never squeeze each other or the device line.
            chips.padding(.leading, faceSize + Theme.gap)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.gutter)
        .padding(.bottom, Theme.gapLoose)
    }

    private let faceSize: CGFloat = 46

    /// Boop's mood in words, labelled, so it doesn't rest on telling the
    /// faces apart. The face already draws in the mood's designs.
    private func moodLabel(_ mood: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Mood").foregroundStyle(Theme.inkFaint)
            Text(mood.capitalized).foregroundStyle(Theme.inkSoft)
                .contentTransition(.opacity)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .fixedSize()
        .animation(.boopSettle, value: mood)
        .accessibilityElement(children: .combine)
    }

    /// Small reminders of what's set in Settings, so a silent Boop never
    /// looks broken. Nothing shows when everything is the usual.
    @ViewBuilder private var chips: some View {
        if let status = model.status {
            let s = status.snapshot
            let all: [(String, String)?] = [
                status.personality == .chatter ? ("bubble.left.and.bubble.right.fill", "Chatter") : nil,
                s.vol == 0 ? ("speaker.slash.fill", "Muted") : nil,
            ]
            let chips = all.compactMap { $0 }
            if !chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.1) { icon, text in
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                            Text(text)
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.well, in: Capsule())
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var tone: Color {
        switch FaceMood(model.status) {
        case .needsYou: Theme.amber
        case .working: Theme.inkSoft
        case .idle, .happy, .asleep, .cheeky: Theme.inkFaint
        }
    }

    private var live: Bool {
        let mood = FaceMood(model.status)
        return mood == .working || mood == .needsYou
    }

    private var headline: String {
        guard let s = model.status?.snapshot else {
            return model.startError == nil ? "Waking up…" : "Not running"
        }
        if s.waiting > 0 { return s.waiting == 1 ? "Needs you" : "\(s.waiting) sessions need you" }
        switch s.base {
        case "working": return s.busy == 1 ? "Working on 1 session" : "Working on \(s.busy) sessions"
        case "idle": return "Hanging out"
        default: return "Napping"
        }
    }

    // MARK: Needs you

    /// The card names the session that has waited longest, as the device
    /// does, but in full: the snapshot's project and thread name are cut to
    /// fit the device. The session list puts it first.
    private func needsYou(_ attn: StateSnapshot.Attention, _ sessions: [SessionSummary]) -> some View {
        let waiting = sessions.first { $0.status == .waiting }
        let project = waiting?.project ?? attn.project
        let name = waiting?.name ?? attn.name
        let agent = HookInstaller.Agent(rawValue: attn.agent)?.displayName ?? attn.agent
        return Card(tone: Theme.amber) {
            HStack(alignment: .top, spacing: Theme.gapSnug + 2) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.amberInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(project.isEmpty ? agent : "\(agent) · \(project)")
                            .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        if let workspace = waiting?.workspace { ThreadName(workspace) }
                    }
                    if !name.isEmpty {
                        Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    }
                    Text("Waiting for you. Answer it in the agent's window.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
                if attn.more > 0 {
                    Text("+\(attn.more) more").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.amberInk)
                }
            }
        }
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        .animation(.boopPop, value: project)
    }

    // MARK: Sessions

    @ViewBuilder private func sessions(_ status: Runtime.Status) -> some View {
        if status.sessions.isEmpty {
            Card {
                HStack(spacing: Theme.gapSnug + 2) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 14)).foregroundStyle(Theme.inkFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No agents awake").font(.system(size: 12, weight: .medium))
                        Text("Start Claude Code or Codex and \(status.name) will notice.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            // A fixed order, so a group doesn't jump to the top when one of
            // its sessions starts waiting and back when it stops.
            let agents = HookInstaller.Agent.allCases.filter { a in status.sessions.contains { $0.agent == a.rawValue } }
            VStack(alignment: .leading, spacing: Theme.gap) {
                ForEach(agents, id: \.self) { agent in
                    VStack(alignment: .leading, spacing: 5) {
                        // A fixed icon width, so the names line up.
                        HStack(spacing: 6) {
                            Image(systemName: agentSymbol(agent.rawValue)).frame(width: 18)
                            Text(agent.displayName)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        ForEach(KeyedSession.rows(status.sessions.filter { $0.agent == agent.rawValue })) { row in
                            SessionRow(project: row.session.project, thread: row.session.name ?? row.session.workspace,
                                       status: row.session.status)
                        }
                    }
                }
            }
            .animation(.boopPop, value: status.sessions)
        }
    }

    // MARK: Notices

    /// What "Jev isn't answering" says, in plain words, by what the person
    /// can do about it (harness/HARNESS.md §7).
    static func brainProblem(_ trouble: BrainTrouble) -> String {
        let meanwhile = "Until Jev answers again, Boop only reacts by its own rules."
        return switch trouble.kind {
        case .credit: "Jev's account is out of credit (\(trouble.why)). Top it up at TypeSafe. \(meanwhile)"
        case .key: "Jev didn't accept the API key (\(trouble.why)). Check the key in Settings. \(meanwhile)"
        case .failing: "The last \(trouble.inARow) tries failed (\(trouble.why)). \(meanwhile)"
        }
    }

    private func notice(_ icon: String, _ tone: Color, _ title: String, _ detail: String,
                        dismiss: (() -> Void)? = nil) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.gapSnug + 2) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tone).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let dismiss {
                    Button(action: { withAnimation(.boopSettle) { dismiss() } }) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.quiet)
                    .padding(.top, -4).padding(.trailing, -6)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Parts

func agentSymbol(_ short: String) -> String {
    switch short {
    case "claude": "chevron.left.forwardslash.chevron.right"
    case "codex": "curlybraces"
    default: "terminal"
    }
}

/// A session keyed by its project and thread and which of those sessions
/// it is, so a row that changes status moves, instead of the row in its old
/// place crossfading to another project.
struct KeyedSession: Identifiable {
    let id: String
    let session: SessionSummary

    static func rows(_ sessions: [SessionSummary]) -> [KeyedSession] {
        var seen: [String: Int] = [:]
        return sessions.map { s in
            let place = s.workspace.map { "\(s.project)/\($0)" } ?? s.project
            let n = seen[place, default: 0]
            seen[place] = n + 1
            return KeyedSession(id: "\(place)#\(n)", session: s)
        }
    }
}

/// A thread's name after its project, small and faint: which worktree or
/// branch, when a project has several sessions.
struct ThreadName: View {
    let name: String
    init(_ name: String) { self.name = name }

    var body: some View {
        Text(name)
            .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.inkSoft)
            .lineLimit(1).truncationMode(.tail)
    }
}

/// One session: the project, its thread, and its status in a chip. The tone also runs
/// down a thin bar on the leading edge, so the amber of a waiting one stands
/// out in a column of greys.
struct SessionRow: View {
    let project: String
    var thread: String?
    let status: SessionSummary.Status

    private var tone: Color {
        switch status {
        case .waiting: Theme.amberInk
        case .working: Theme.ink
        case .idle: Theme.inkSoft
        }
    }

    private var bar: Color {
        switch status {
        case .waiting: Theme.amber
        case .working: Theme.inkSoft
        case .idle: Theme.hairlineStrong
        }
    }

    private var label: String {
        switch status {
        case .waiting: "needs you"
        case .working: "working"
        case .idle: "idle"
        }
    }

    var body: some View {
        HStack(spacing: Theme.gapSnug) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(project.isEmpty ? "Unknown project" : project)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                if let thread { ThreadName(thread) }
            }
            Spacer(minLength: Theme.gapTight)
            StatusChip(text: label, tone: tone)
        }
        .padding(.leading, 13).padding(.trailing, 8).padding(.vertical, 7)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.wellRadius))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(bar).frame(width: 3).padding(.vertical, 6).padding(.leading, 1)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.wellRadius).strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Whether Boop's body is connected, as plain words, so it doesn't look like
/// a button. Which board it is stays out of sight.
struct DeviceLine: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let connected = model.status?.connected == true
        HStack(spacing: 5) {
            Circle().fill(connected ? Theme.sage : Theme.inkFaint).frame(width: 6, height: 6)
            Text(connected ? "Connected" : model.link == .none ? "No device" : "Looking…")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .fixedSize()
        .padding(.trailing, 2)
        .help(connected ? "Boop's body is connected" : "Boop's body isn't connected yet. Plug it into USB power.")
        .animation(.boopSettle, value: connected)
    }
}
