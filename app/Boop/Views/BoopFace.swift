import AppKit
import BoopKit
import SwiftUI

/// What the little face shows. The Mac never plays Boop's moments; this is
/// just enough of the device's face that the popover and the menu bar read
/// as the same creature (UX.md §7).
enum FaceMood: Equatable {
    case asleep, idle, working, needsYou, happy

    init(_ status: Runtime.Status?) {
        guard let s = status?.snapshot else {
            self = .asleep
            return
        }
        if s.wait > 0 {
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

/// The device's face geometry (firmware `face.cpp`), in its pixels: solid
/// rounded eyes a bit taller than wide, set wide apart, and a small smile.
private enum FaceGeometry {
    static let eyeW: CGFloat = 60, eyeH: CGFloat = 80, eyeR: CGFloat = 22
    static let eyeGap: CGFloat = 67
    static let lookX: CGFloat = 26, lookY: CGFloat = 16, turn: CGFloat = 0.11
    static let mouthY: CGFloat = 54, mouthHalfW: CGFloat = 14, mouthThick: CGFloat = 4, mouthBend: CGFloat = 7
    /// Eye tops to the bottom of the mouth, so the face centres on its middle.
    static let drop: CGFloat = (mouthY + mouthThick / 2 - eyeH / 2) / 2
    static let span: CGFloat = 2 * eyeGap + eyeW
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
        var tint = Theme.oat
        var smile: CGFloat = 1
    }

    private var pose: Pose {
        var p = Pose()
        switch mood {
        case .asleep:
            p.open = 0.34
            p.lookY = 0.5
            p.tint = Theme.oat.opacity(0.7)
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
        case .happy:
            p.tint = Color(hex: "#FFE3A8")
            p.smile = 1.6
        }
        if blink { p.open = min(p.open, 0.08) }
        return p
    }

    private func face(k: CGFloat, pose: Pose) -> some View {
        let g = FaceGeometry.self
        let w = g.eyeW * k * pose.scale, h = g.eyeH * k * pose.scale
        let dx = g.lookX * k * pose.lookX, dy = g.lookY * k * pose.lookY
        let centreY = size / 2 - g.drop * k
        return ZStack {
            ForEach([-1, 1], id: \.self) { (side: Int) in
                // The eye on the side Boop looks towards grows a little, as
                // if it turned its head.
                let grow = 1 + g.turn * max(0, pose.lookX * CGFloat(side))
                let openH = max(h * grow * pose.open, 1.2)
                RoundedRectangle(cornerRadius: min(g.eyeR * k * grow, openH / 2), style: .continuous)
                    .fill(pose.tint)
                    .frame(width: w * grow, height: openH)
                    // Lids come down from the top, so a closing eye keeps its bottom.
                    .position(x: size / 2 + CGFloat(side) * g.eyeGap * k + dx,
                              y: centreY + dy + (h * grow - openH) / 2)
            }
            Smile(bend: g.mouthBend * k * pose.smile)
                .stroke(pose.tint, style: StrokeStyle(lineWidth: max(g.mouthThick * k, 1.1), lineCap: .round))
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

/// The menu-bar icon: Boop's eyes. Closed while asleep, open while agents
/// idle, with a small dot while they work, and amber when something needs you.
enum MenuBarIcon {
    static func image(_ mood: FaceMood) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            let colour: NSColor = mood == .needsYou ? NSColor(hex: Palette.deviceAmber) : .black
            colour.setFill()
            colour.setStroke()
            let eyeW: CGFloat = 4.6, eyeH: CGFloat = 6.2
            let centres: [CGFloat] = [5.6, 14.4]
            for x in centres {
                let rect: NSRect
                if mood == .asleep {
                    rect = NSRect(x: x - eyeW / 2, y: 8.6, width: eyeW, height: 1.9)
                } else {
                    rect = NSRect(x: x - eyeW / 2, y: 4.6, width: eyeW, height: eyeH)
                }
                NSBezierPath(roundedRect: rect, xRadius: min(1.9, rect.height / 2), yRadius: min(1.9, rect.height / 2)).fill()
            }
            let smile = NSBezierPath()
            smile.lineWidth = 1.1
            smile.lineCapStyle = .round
            let y: CGFloat = mood == .asleep ? 13.2 : 13.4
            smile.move(to: NSPoint(x: 8.6, y: y))
            smile.curve(to: NSPoint(x: 11.4, y: y), controlPoint1: NSPoint(x: 9.3, y: y + 1.3),
                        controlPoint2: NSPoint(x: 10.7, y: y + 1.3))
            smile.stroke()
            if mood == .working || mood == .needsYou {
                NSBezierPath(ovalIn: NSRect(x: 16.6, y: 0.6, width: 3.2, height: 3.2)).fill()
            }
            return true
        }
        image.isTemplate = mood != .needsYou
        image.accessibilityDescription = "Boop"
        return image
    }
}
