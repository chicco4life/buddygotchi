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
                        notice("arrow.clockwise", Theme.amberInk, "Restart your agent sessions",
                               "Open sessions pick up Boop's hooks when they restart.") {
                            model.restartAgents = false
                        }
                    }
                    if let status = model.status {
                        if let attn = status.snapshot.attn { needsYou(attn) }
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
        HStack(spacing: Theme.gap) {
            HStack(spacing: Theme.gap) {
                BoopFace(mood: FaceMood(model.status), size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name).font(.boop(18)).lineLimit(1)
                    HStack(spacing: 6) {
                        StateDot(tone: tone, pulsing: live)
                        Text(headline).font(.system(size: 12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    .animation(.boopSettle, value: headline)
                    modes
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if model.status != nil {
                VStack(alignment: .trailing, spacing: 6) {
                    DevicePill(model: model)
                    TalkButton(model: model)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.gutter)
        .padding(.bottom, Theme.gapLoose)
    }

    /// Small reminders of the modes set in Settings, so a silent Boop never
    /// looks broken. Nothing shows when everything is normal.
    @ViewBuilder private var modes: some View {
        if let status = model.status {
            let s = status.snapshot
            let all: [(String, String)?] = [
                status.mode == .chatty ? ("bubble.left.and.bubble.right.fill", "Chatty") : nil,
                status.mode == .calm ? ("leaf.fill", "Calm") : nil,
                s.quiet > 0 ? ("zzz", "Quiet · \(s.quiet) min") : nil,
                s.vol == 0 ? ("speaker.slash.fill", "Muted") : nil,
            ]
            let chips = all.compactMap { $0 }
            if !chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.1) { icon, text in
                        Label(text, systemImage: icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.well, in: Capsule())
                    }
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }

    private var tone: Color {
        switch FaceMood(model.status) {
        case .listening: Theme.recording
        case .needsYou: Theme.amber
        case .working: Theme.accent
        case .idle, .happy: Theme.sage
        case .asleep: Theme.inkFaint
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

    private func needsYou(_ attn: StateSnapshot.Attention) -> some View {
        Card(tone: Theme.amber) {
            HStack(alignment: .top, spacing: Theme.gapSnug + 2) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.amberInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(agentName(attn.agent)) · \(attn.project)")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
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
        .animation(.boopPop, value: attn.project)
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
            let agents = status.sessions.map(\.agent).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            VStack(alignment: .leading, spacing: Theme.gap) {
                ForEach(agents, id: \.self) { agent in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(agentName(agent), systemImage: agentSymbol(agent))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.leading, 2)
                        ForEach(Array(status.sessions.filter { $0.agent == agent }.enumerated()), id: \.offset) { _, row in
                            SessionRow(project: row.project, status: row.status)
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

/// One session: the project, and its status in a chip. The tone also runs
/// down a thin bar on the leading edge, so a column of rows scans by colour.
struct SessionRow: View {
    let project: String
    let status: SessionSummary.Status

    private var tone: Color {
        switch status {
        case .waiting: Theme.amberInk
        case .working: Theme.accentInk
        case .idle: Theme.inkSoft
        }
    }

    private var bar: Color {
        switch status {
        case .waiting: Theme.amber
        case .working: Theme.accent
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
            Label(on ? "Send" : "Talk", systemImage: on ? "arrow.up" : "mic.fill")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(RowButtonStyle(filled: on, fill: Theme.recording))
        .fixedSize()
        .help(on ? "Stop listening and send what \(model.name) heard"
                 : "Talk to \(model.name) with the Mac's microphone. It stops by itself after 30 seconds")
        .accessibilityLabel(on ? "Stop listening and send" : "Talk to \(model.name)")
        .animation(.boopSettle, value: on)
    }
}

/// Whether Boop's body is connected. Which board it is stays out of sight.
struct DevicePill: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let connected = model.status?.connected == true
        HStack(spacing: 5) {
            Circle().fill(connected ? Theme.sage : Theme.inkFaint).frame(width: 6, height: 6)
            Text(connected ? "Connected" : model.link == .none ? "No device" : "Looking…")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .fixedSize()
        // Just under half the height: an exact capsule outline picks up
        // straight edges when rendered offscreen.
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .help(connected ? "Boop's body is connected" : "Boop's body isn't connected yet. Plug it into USB power.")
        .animation(.boopSettle, value: connected)
    }
}
