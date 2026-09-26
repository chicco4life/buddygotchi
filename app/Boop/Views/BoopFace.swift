import AppKit
import BoopKit
import SwiftUI

/// What the little face shows. The Mac never plays Boop's moments; this is
/// just enough of the device's face that the popover and the menu bar read
/// as the same creature (UX.md §7).
enum FaceMood: Equatable {
    case asleep, idle, working, needsYou, happy, listening

    init(_ status: Runtime.Status?) {
        guard let status else {
            self = .asleep
            return
        }
        let s = status.snapshot
        if status.listening {
            self = .listening
        } else if s.wait > 0 {
            self = .needsYou
        } else {
            switch s.base {
            case "working": self = .working
            case "idle": self = .idle
            default: self = .asleep
            }
        }
    }
}

/// The device's face geometry (firmware `face.cpp`), in its pixels: square
/// window eyes of four panes around a one-block cross, set wide apart, pink
/// cheeks under them and a flat bar mouth. The device draws it in 3 px
/// blocks; the tile is too small for the grid to show, so it keeps the shapes.
private enum FaceGeometry {
    static let eye: CGFloat = 39, block: CGFloat = 3
    static let eyeGap: CGFloat = 72
    static let lookX: CGFloat = 24, lookY: CGFloat = 15, turn: CGFloat = 0.11
    static let mouthY: CGFloat = 45, mouthHalfW: CGFloat = 20, mouthThick: CGFloat = 6, mouthBend: CGFloat = 9
    static let blushDx: CGFloat = 22, blushDy: CGFloat = 40, blushW: CGFloat = 12, blushH: CGFloat = 9
    /// Eye tops to the bottom of the mouth, so the face centres on its middle.
    static let drop: CGFloat = (mouthY + mouthThick / 2 - eye / 2) / 2
    static let span: CGFloat = 2 * eyeGap + eye
}

/// Boop's face on a small black-glass tile. It blinks now and then, glances
/// about while agents work, and looks up at you when something needs you.
struct BoopFace: View {
    var mood: FaceMood
    var size: CGFloat = 40
    var animated = true

    @ViewState private var blink = false
    @ViewState private var gaze: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotion) private var still

    var body: some View {
        let k = 0.72 * size / FaceGeometry.span
        let pose = pose
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Theme.glass)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(mood == .needsYou ? Theme.amber : Theme.hairlineStrong.opacity(0.6),
                              lineWidth: mood == .needsYou ? max(1.5, size * 0.04) : 1)
            face(k: k, pose: pose)
        }
        .frame(width: size, height: size)
        .animation(.boopEase(0.35), value: mood)
        .task(id: mood) { await live() }
        .accessibilityHidden(true)
    }

    private struct Pose {
        var open: CGFloat = 1
        var lookX: CGFloat = 0
        var lookY: CGFloat = 0
        var scale: CGFloat = 1
        var tint = Theme.eye
        var smile: CGFloat = 0  // at rest, a flat dash, as on the device
        var squint: CGFloat = 0  // happy: the bottom of the eye rises
    }

    private var pose: Pose {
        var p = Pose()
        switch mood {
        case .asleep:
            p.open = 0.34
            p.lookY = 0.5
            p.tint = Theme.eye.opacity(0.7)
            p.smile = 0.3
        case .idle:
            break
        case .working:
            p.open = 0.86
            p.lookX = gaze
            p.lookY = 0.25
        case .needsYou:
            p.lookY = -0.6
            p.scale = 1.06
            p.smile = 0.5
        case .happy:  // the device's happy squint and a small smile
            p.squint = 0.25
            p.smile = 0.6
        case .listening:
            p.lookY = -0.35
            p.scale = 1.1
            p.smile = 0.6
        }
        if blink { p.open = min(p.open, 0.08) }
        return p
    }

    private func face(k: CGFloat, pose: Pose) -> some View {
        let g = FaceGeometry.self
        let dx = g.lookX * k * pose.lookX, dy = g.lookY * k * pose.lookY
        let centreY = size / 2 - g.drop * k
        return ZStack {
            ForEach([-1, 1], id: \.self) { (side: Int) in
                // The eye on the side Boop looks towards grows a little, as
                // if it turned its head.
                let grow = 1 + g.turn * max(0, pose.lookX * CGFloat(side))
                let x = size / 2 + CGFloat(side) * g.eyeGap * k + dx, y = centreY + dy
                Cheeks(k: k)
                    .fill(Theme.blush)
                    .frame(width: (2 * g.blushW + g.block) * k, height: g.blushH * k)
                    .position(x: x + CGFloat(side) * g.blushDx * k, y: y + g.blushDy * k)
                Panes(open: pose.open, squint: pose.squint, gap: g.block * k * pose.scale * grow)
                    .fill(pose.tint)
                    .frame(width: g.eye * k * pose.scale * grow, height: g.eye * k * pose.scale * grow)
                    .position(x: x, y: y)
            }
            Smile(bend: g.mouthBend * k * pose.smile)
                .stroke(pose.tint, style: StrokeStyle(lineWidth: max(g.mouthThick * k, 1.1), lineCap: .butt))
                .frame(width: max(2 * g.mouthHalfW * k, 4), height: max(g.mouthBend * k * pose.smile, 0.5))
                .position(x: size / 2 + dx * 0.45, y: centreY + g.mouthY * k + dy * 0.45)
        }
    }

    /// Blinks every few seconds; while working, the gaze drifts side to side.
    private func live() async {
        guard animated, !reduceMotion, !still, mood != .asleep else { return }
        var left = true
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2400...5200)))
            if Task.isCancelled { return }
            if mood == .working && Bool.random() {
                withAnimation(.boopEase(0.5)) { gaze = left ? -0.7 : 0.6 }
                left.toggle()
                continue
            }
            withAnimation(.easeIn(duration: 0.07)) { blink = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.12)) { blink = false }
        }
    }
}

/// A window eye: four panes around a cross, squeezing about its middle as it
/// closes, and one bar once it's too thin for panes (as the device does).
/// Happy, the bottom rises (`squint`) and the top stays put.
private struct Panes: Shape {
    var open: CGFloat
    var squint: CGFloat = 0
    var gap: CGFloat

    var animatableData: CGFloat {
        get { open }
        set { open = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = max(rect.height * open, gap)
        let top = rect.midY - h / 2
        let r = min(gap / 3, 1)
        if h < gap * 7 {
            p.addRoundedRect(in: CGRect(x: rect.minX, y: top, width: rect.width, height: h),
                             cornerSize: CGSize(width: r, height: r))
            return p
        }
        let pw = (rect.width - gap) / 2, ph = (h - gap) / 2
        let cut = h * squint
        for col in 0..<2 {
            for row in 0..<2 {
                let pane = CGRect(x: rect.minX + CGFloat(col) * (pw + gap), y: top + CGFloat(row) * (ph + gap),
                                  width: pw, height: row == 1 ? max(ph - cut, 0) : ph)
                p.addRoundedRect(in: pane, cornerSize: CGSize(width: r, height: r))
            }
        }
        return p
    }
}

/// The cheeks under one eye: two pink blocks a block apart.
private struct Cheeks: Shape {
    var k: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let gap = FaceGeometry.block * k, w = (rect.width - gap) / 2
        let r = min(gap / 3, 1)
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height),
                         cornerSize: CGSize(width: r, height: r))
        p.addRoundedRect(in: CGRect(x: rect.minX + w + gap, y: rect.minY, width: w, height: rect.height),
                         cornerSize: CGSize(width: r, height: r))
        return p
    }
}

private struct Smile: Shape {
    var bend: CGFloat

    var animatableData: CGFloat {
        get { bend }
        set { bend = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY - bend / 2))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY - bend / 2),
                       control: CGPoint(x: rect.midX, y: rect.midY + bend * 1.1))
        return p
    }
}

/// The menu-bar icon: Boop's window eyes. Closed while asleep, open while agents
/// idle, with a small dot while they work, amber when something needs you,
/// and red with a bigger dot while the Mac's mic is on.
enum MenuBarIcon {
    static func image(_ mood: FaceMood) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            let colour: NSColor = switch mood {
            case .needsYou: NSColor(hex: Palette.deviceAmber)
            case .listening: NSColor(hex: Palette.recording)
            default: .black
            }
            colour.setFill()
            colour.setStroke()
            // Window eyes, as on the device: four 2.2 pt panes a 0.8 pt cross
            // apart, or a bar while asleep.
            let pane: CGFloat = 2.2, gap: CGFloat = 0.8, eye = 2 * pane + gap
            let centres: [CGFloat] = [5.4, 14.6]
            for x in centres {
                if mood == .asleep {
                    NSBezierPath(rect: NSRect(x: x - eye / 2, y: 8.6, width: eye, height: 1.6)).fill()
                    continue
                }
                for col in 0..<2 {
                    for row in 0..<2 {
                        NSBezierPath(rect: NSRect(x: x - eye / 2 + CGFloat(col) * (pane + gap),
                                                  y: 4.6 + CGFloat(row) * (pane + gap), width: pane, height: pane)).fill()
                    }
                }
            }
            let smile = NSBezierPath()
            smile.lineWidth = 1.1
            smile.lineCapStyle = .round
            let y: CGFloat = mood == .asleep ? 13.2 : 13.4
            smile.move(to: NSPoint(x: 8.6, y: y))
            smile.curve(to: NSPoint(x: 11.4, y: y), controlPoint1: NSPoint(x: 9.3, y: y + 1.3),
                        controlPoint2: NSPoint(x: 10.7, y: y + 1.3))
            smile.stroke()
            if mood == .listening {
                NSBezierPath(ovalIn: NSRect(x: 15.6, y: 0, width: 4.4, height: 4.4)).fill()
            } else if mood == .working || mood == .needsYou {
                NSBezierPath(ovalIn: NSRect(x: 16.6, y: 0.6, width: 3.2, height: 3.2)).fill()
            }
            return true
        }
        image.isTemplate = mood != .needsYou && mood != .listening
        image.accessibilityDescription = "Boop"
        return image
    }
}
