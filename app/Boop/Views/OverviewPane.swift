import BoopKit
import SwiftUI

/// Overview, top to bottom: Boop and how things are, who needs you, and
/// every session by agent (UX.md §7). Controls live in Settings; the one
/// exception is the Talk button.
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
                    if let why = model.talkError {
                        notice("mic.slash.fill", Theme.clayInk, "\(model.name) can't hear you", why) {
                            model.talkError = nil
                        }
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
                    BoopFace(mood: FaceMood(model.status), size: faceSize)
                    VStack(alignment: .leading, spacing: 3) {
                        // A long name shrinks a little before it's cut.
                        Text(model.name).font(.boop(18)).lineLimit(1).minimumScaleFactor(0.8)
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
                    VStack(alignment: .trailing, spacing: 6) {
                        DeviceLine(model: model)
                        TalkButton(model: model)
                    }
                }
            }
            // Under the name, the full width of the popover, so three
            // chips never squeeze each other or the Talk column.
            modes.padding(.leading, faceSize + Theme.gap)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.gutter)
        .padding(.bottom, Theme.gapLoose)
    }

    private let faceSize: CGFloat = 46

    /// Small reminders of what's set in Settings, so a silent Boop never
    /// looks broken. Nothing shows when everything is the usual.
    @ViewBuilder private var modes: some View {
        if let status = model.status {
            let s = status.snapshot
            let all: [(String, String)?] = [
                status.personality == .chatter ? ("bubble.left.and.bubble.right.fill", "Chatter") : nil,
                s.quiet > 0 ? ("zzz", "Quiet · \(s.quiet) min") : nil,
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
        case .listening: Theme.recording
        case .needsYou: Theme.amber
        case .working: Theme.inkSoft
        case .idle, .happy, .asleep, .cheeky: Theme.inkFaint
        }
    }

    private var live: Bool {
        let mood = FaceMood(model.status)
        return mood == .working || mood == .needsYou || mood == .listening
    }

    private var headline: String {
        guard let s = model.status?.snapshot else {
            return model.startError == nil ? "Waking up…" : "Not running"
        }
        if model.listening { return "Listening…" }
        if s.wait > 0 { return s.wait == 1 ? "Needs you" : "\(s.wait) sessions need you" }
        switch s.base {
        case "working": return s.busy == 1 ? "Working on 1 session" : "Working on \(s.busy) sessions"
        case "idle": return "Hanging out"
        default: return "Napping"
        }
    }

    // MARK: Needs you

    /// The card names the session that has waited longest, as the device
    /// does, but in full: the snapshot's project is cut to fit the device.
    /// The session list puts it first.
    private func needsYou(_ attn: StateSnapshot.Attention, _ sessions: [SessionSummary]) -> some View {
        let project = sessions.first { $0.status == .waiting }?.project ?? attn.project
        return Card(tone: Theme.amber) {
            HStack(alignment: .top, spacing: Theme.gapSnug + 2) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.amberInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.isEmpty ? agentName(attn.agent) : "\(agentName(attn.agent)) · \(project)")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
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
        let s = status.snapshot
        if status.sessions.isEmpty {
            Card {
                HStack(spacing: Theme.gapSnug + 2) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 14)).foregroundStyle(Theme.inkFaint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No agents awake").font(.system(size: 12, weight: .medium))
                        Text("Start Claude Code or Codex and \(s.name) will notice.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            // A fixed order, so a group doesn't jump to the top when one of
            // its sessions starts waiting and back when it stops.
            let agents = HookInstaller.Agent.allCases.map(\.rawValue).filter { a in status.sessions.contains { $0.agent == a } }
            VStack(alignment: .leading, spacing: Theme.gap) {
                ForEach(agents, id: \.self) { agent in
                    VStack(alignment: .leading, spacing: 5) {
                        // A fixed icon width, so the names line up.
                        HStack(spacing: 6) {
                            Image(systemName: agentSymbol(agent)).frame(width: 18)
                            Text(agentName(agent))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        ForEach(KeyedSession.rows(status.sessions.filter { $0.agent == agent })) { row in
                            SessionRow(project: row.session.project, status: row.session.status)
                        }
                    }
                }
            }
            .animation(.boopPop, value: status.sessions)
        }
    }

    // MARK: Notices

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

func agentName(_ short: String) -> String {
    switch short {
    case "claude": "Claude Code"
    case "codex": "Codex"
    default: short.capitalized
    }
}

func agentSymbol(_ short: String) -> String {
    switch short {
    case "claude": "chevron.left.forwardslash.chevron.right"
    case "codex": "curlybraces"
    default: "terminal"
    }
}

/// A session keyed by its project and which of that project's sessions it
/// is, so a row that changes status moves, instead of the row in its old
/// place crossfading to another project.
struct KeyedSession: Identifiable {
    let id: String
    let session: SessionSummary

    static func rows(_ sessions: [SessionSummary]) -> [KeyedSession] {
        var seen: [String: Int] = [:]
        return sessions.map { s in
            let n = seen[s.project, default: 0]
            seen[s.project] = n + 1
            return KeyedSession(id: "\(s.project)#\(n)", session: s)
        }
    }
}

/// One session: the project, and its status in a chip. The tone also runs
/// down a thin bar on the leading edge, so the amber of a waiting one stands
/// out in a column of greys.
struct SessionRow: View {
    let project: String
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
            Text(project.isEmpty ? "Unknown project" : project)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
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

/// Push-to-talk from the Mac (UX.md §5): click to talk, click again to send.
/// While the mic is on it turns recording red and says Send.
struct TalkButton: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let on = model.listening
        Button(action: model.toggleTalk) {
            // One width for both words, so the button doesn't jump.
            Label(on ? "Send" : "Talk", systemImage: on ? "arrow.up" : "mic.fill")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(width: 50)
        }
        .buttonStyle(RowButtonStyle(filled: on ? Theme.send : nil))
        .fixedSize()
        .help(on ? "Stop listening and send what \(model.name) heard"
                 : "Talk to \(model.name) with the Mac's microphone. It stops by itself after 30 seconds")
        .accessibilityLabel(on ? "Stop listening and send" : "Talk to \(model.name)")
        .animation(.boopSettle, value: on)
    }
}

/// Whether Boop's body is connected, as plain words over the Talk button, so
/// it doesn't look like a second button. Which board it is stays out of sight.
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
