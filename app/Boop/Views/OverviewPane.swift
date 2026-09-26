import BoopKit
import SwiftUI

/// Overview, top to bottom: Boop and how things are, who needs you, every
/// session by agent, and what you've done together (UX.md §7). Controls
/// live in Settings; this pane only shows.
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
                    if model.restartAgents {
                        notice("arrow.clockwise", Theme.amberInk, "Restart your agent sessions",
                               "Open sessions pick up Boop's hooks when they restart.") {
                            model.restartAgents = false
                        }
                    }
                    if let s = model.status?.snapshot {
                        if let attn = s.attn { needsYou(attn) }
                        PaneSection(s.threads.isEmpty ? "Sessions" : "Sessions · \(s.threads.count)") { sessions(s) }
                        if let status = model.status { PaneSection("Together") { together(status) } }
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
            Spacer(minLength: 0)
            if model.status != nil { DevicePill(model: model) }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.gutter)
        .padding(.bottom, Theme.gapLoose)
        .accessibilityElement(children: .combine)
    }

    /// Small reminders of the modes set in Settings, so a silent Boop never
    /// looks broken. Nothing shows when everything is normal.
    @ViewBuilder private var modes: some View {
        if let status = model.status {
            let s = status.snapshot
            let all: [(String, String)?] = [
                s.focus ? ("moon.fill", "Focus") : nil,
                s.quiet > 0 ? ("zzz", "Quiet · \(s.quiet) min") : nil,
                s.vol == 0 && !s.focus ? ("speaker.slash.fill", "Muted") : nil,
                status.away ? ("figure.walk", "Away") : nil,
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
        case .needsYou: Theme.amber
        case .working: Theme.accent
        case .idle, .happy: Theme.sage
        case .asleep: Theme.inkFaint
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
        if s.wait > 0 { return s.wait == 1 ? "Needs you" : "\(s.wait) sessions need you" }
        switch s.base {
        case "working": return s.busy == 1 ? "Working on 1 session" : "Working on \(s.busy) sessions"
        case "idle": return "Hanging out"
        default: return s.night ? "Asleep for the night" : "Napping"
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

    @ViewBuilder private func sessions(_ s: StateSnapshot) -> some View {
        if s.threads.isEmpty {
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
            let agents = s.threads.map { $0[0] }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            VStack(alignment: .leading, spacing: Theme.gap) {
                ForEach(agents, id: \.self) { agent in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(agentName(agent), systemImage: agentSymbol(agent))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.leading, 2)
                        ForEach(Array(s.threads.filter { $0[0] == agent }.enumerated()), id: \.offset) { _, row in
                            SessionRow(project: row[1], status: row[2])
                        }
                    }
                }
            }
            .animation(.boopPop, value: s.threads)
        }
    }

    // MARK: Together

    private func together(_ status: Runtime.Status) -> some View {
        let s = status.snapshot
        return Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: Theme.gap) {
                    LevelRing(level: s.level, progress: s.prog)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Level \(s.level)").font(.boop(14))
                        Text("\(s.prog)% of the way to level \(s.level + 1)")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                Hairline()
                HStack(spacing: 0) {
                    stat(status.finished, status.finished == 1 ? "task finished" : "tasks finished")
                    stat(status.projects, status.projects == 1 ? "project" : "projects")
                    stat(s.days, s.days == 1 ? "day together" : "days together")
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value.formatted()).font(.boop(17)).contentTransition(.numericText())
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
    let status: String

    private var tone: Color {
        switch status {
        case "wait": Theme.amberInk
        case "work": Theme.accentInk
        default: Theme.inkSoft
        }
    }

    private var bar: Color {
        switch status {
        case "wait": Theme.amber
        case "work": Theme.accent
        default: Theme.hairlineStrong
        }
    }

    private var label: String {
        switch status {
        case "wait": "needs you"
        case "work": "working"
        default: "idle"
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

/// The device's stats ring: progress to the next level, the level inside.
struct LevelRing: View {
    let level: Int
    let progress: Int
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().stroke(Theme.well, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 100)) / 100)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)").font(.boop(14)).contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .animation(.boopSettle, value: progress)
        .accessibilityHidden(true)
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
