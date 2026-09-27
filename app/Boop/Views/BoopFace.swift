import AppKit
import BoopKit
import SwiftUI

/// What the little face shows. The Mac never plays Boop's moments; this is
/// just enough of the device's face that the popover and the menu bar read
/// as the same creature (UX.md §6).
enum FaceMood: Hashable {
    case asleep, idle, working, needsYou, happy
    /// Setup's preview of a cheeky Boop: a sidelong look and a smile.
    case cheeky

    init(_ status: Runtime.Status?) {
        guard let status else {
            self = .asleep
            return
        }
        let s = status.snapshot
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

/// The device's face (firmware `face.cpp`) in its own blocks: window eyes
/// 13 blocks square, four panes around a one-block cross, their centres 24
/// blocks either side; two pink 4×3 cheeks under each eye towards the
/// outside; and a bar mouth two blocks thick, 15 blocks under the eyes.
private enum FaceGrid {
    static let eye: CGFloat = 13, eyeGap = 24
    static let lookX: CGFloat = 8, lookY: CGFloat = 5, turn: CGFloat = 0.11
    static let mouthRow = 15, mouthWide: CGFloat = 13.33, mouthFollow: CGFloat = 0.45
    static let cheekRow = 12, cheekW = 4, cheekH = 3, cheekIn = 3
    /// The eyes' centre row sits this far above the face's middle (eye tops
    /// to the mouth's bottom), so the face centres in the tile.
    static let drop = 5
    /// Eye edge to eye edge, the width the tile's 72% is measured on.
    static let span: CGFloat = 61
}

/// Boop's face on a small black-glass tile, drawn as the device draws it: in
/// square blocks on a grid snapped to the screen's pixels, so it's as crisp
/// as the device and moves a block at a time. It blinks now and then, glances
/// about while agents work, and looks up at you when something needs you.
struct BoopFace: View {
    var mood: FaceMood
    var size: CGFloat = 40

    @ViewState private var blink = false
    @ViewState private var gaze: CGFloat = -0.25
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stillMotion) private var still
    @Environment(\.displayScale) private var scale

    var body: some View {
        // Whole pixels per block where the tile is big enough for the grid;
        // a 1× screen's small tile keeps the shapes instead.
        let fit = 0.72 * size / FaceGrid.span
        let pixels = (fit * scale).rounded(.down)
        let block = pixels >= 1 ? pixels / scale : fit
        let pose = pose
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Theme.glass)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(mood == .needsYou ? Theme.amber : Theme.hairlineStrong.opacity(0.6),
                              lineWidth: mood == .needsYou ? max(1.5, size * 0.04) : 1)
            FaceBlocks(pose: pose, part: .cheeks, block: block, scale: scale).fill(Theme.blush)
            FaceBlocks(pose: pose, part: .features, block: block, scale: scale)
                .fill(mood == .asleep ? Theme.eye.opacity(0.7) : Theme.eye)
        }
        .frame(width: size, height: size)
        .animation(.boopEase(0.35), value: mood)
        .task(id: mood) { await live() }
        .accessibilityHidden(true)
    }

    /// The device's looks (firmware `anim.cpp`), near enough.
    private var pose: FacePose {
        var p = FacePose()
        switch mood {
        case .asleep:
            p.open = 0
            p.lookY = 0.6
            p.mouth = 0.6
        case .idle:
            break
        case .working:
            p.lid = 0.18
            p.lookX = gaze
            p.lookY = 0.35
            p.mouth = 0.7
        case .needsYou:  // turned to you and leaning in
            p.size = 1.08
            p.lookY = -0.6
            p.mouth = 0.55
        case .happy:  // the squint and a small "u"
            p.squint = 0.25
            p.smile = 1
        case .cheeky:
            p.lid = 0.25
            p.lookX = 0.6
            p.smile = 1
        }
        if blink { p.open = min(p.open, 0.08) }
        return p
    }

    /// Blinks every few seconds; while working, the gaze drifts side to side.
    private func live() async {
        guard !reduceMotion, !still, mood != .asleep else { return }
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

/// Where the face is, as numbers that blend: SwiftUI eases between two
/// poses and each frame snaps to the grid, as the device's blend does.
private struct FacePose: VectorArithmetic {
    var open: CGFloat = 1, lookX: CGFloat = 0, lookY: CGFloat = 0, size: CGFloat = 1
    var lid: CGFloat = 0  // rows off the top, as a share of the eye
    var squint: CGFloat = 0  // happy: rows off the bottom
    var smile: CGFloat = 0  // from 0.3 the bar becomes a small "u"
    var mouth: CGFloat = 1  // the bar's width, as a share of an eye

    private static let fields: [WritableKeyPath<FacePose, CGFloat> & Sendable] =
        [\.open, \.lookX, \.lookY, \.size, \.lid, \.squint, \.smile, \.mouth]

    private static func combine(_ a: FacePose, _ b: FacePose, _ op: (CGFloat, CGFloat) -> CGFloat) -> FacePose {
        var out = a
        for f in fields { out[keyPath: f] = op(a[keyPath: f], b[keyPath: f]) }
        return out
    }

    static var zero: FacePose { FacePose(open: 0, size: 0, mouth: 0) }
    static func + (a: FacePose, b: FacePose) -> FacePose { combine(a, b, +) }
    static func - (a: FacePose, b: FacePose) -> FacePose { combine(a, b, -) }
    mutating func scale(by rhs: Double) { for f in Self.fields { self[keyPath: f] *= rhs } }
    var magnitudeSquared: Double { Self.fields.reduce(0) { $0 + Double(self[keyPath: $1] * self[keyPath: $1]) } }
}

/// The face's blocks, in one colour: the eyes and mouth, or the cheeks.
private struct FaceBlocks: Shape {
    enum Part { case features, cheeks }

    var pose: FacePose
    let part: Part
    let block: CGFloat
    let scale: CGFloat

    var animatableData: FacePose {
        get { pose }
        set { pose = newValue }
    }

    /// The nearest odd count of blocks (12.x and 13.x → 13), so a shape centres on a block.
    private func odd(_ blocks: CGFloat, least: Int) -> Int {
        max(least, 2 * Int((blocks / 2).rounded(.down)) + 1)
    }

    func path(in rect: CGRect) -> Path {
        let g = FaceGrid.self
        var path = Path()
        // Block (0, 0) is the tile's middle; its corner lands on a pixel.
        let x0 = ((rect.midX - block / 2) * scale).rounded() / scale
        let y0 = ((rect.midY - block / 2) * scale).rounded() / scale
        func fill(_ bx: Int, _ by: Int, _ w: Int = 1, _ h: Int = 1) {
            path.addRect(CGRect(x: x0 + CGFloat(bx) * block, y: y0 + CGFloat(by) * block,
                                width: CGFloat(w) * block, height: CGFloat(h) * block))
        }
        let p = pose
        let rest = -g.drop
        for side in [-1, 1] {
            // The eye on the side Boop looks towards comes nearer and grows,
            // the other shrinks, as if it turned its head.
            let turn = 1 + g.turn * p.lookX * CGFloat(side)
            let ex = Int((CGFloat(side * g.eyeGap) + p.lookX * g.lookX).rounded())
            let ey = rest + Int((p.lookY * g.lookY).rounded())
            if part == .cheeks {
                let happy = p.squint > 0.1 ? 1 : 0  // the cheeks rise with the squint
                let inner = side > 0 ? ex + g.cheekIn : ex - g.cheekIn - 2 * g.cheekW
                for k in 0..<2 { fill(inner + k * (g.cheekW + 1), ey + g.cheekRow - happy, g.cheekW, g.cheekH) }
                continue
            }
            let wb = odd(g.eye * p.size * turn, least: 3)
            let hb = odd(g.eye * p.size * turn * max(p.open, 0), least: 1)
            let panes = wb >= 7 && hb >= 7
            let top = ey - hb / 2
            let cutTop = Int((CGFloat(hb) * max(p.lid, 0) + 0.5).rounded(.down))
            let keep = Int((CGFloat(hb) * (1 - max(p.squint, 0)) + 0.5).rounded(.down))
            for row in cutTop..<max(cutTop, keep) where !(panes && row == hb / 2) {
                if panes {
                    fill(ex - wb / 2, top + row, wb / 2)
                    fill(ex + 1, top + row, wb / 2)
                } else {
                    fill(ex - wb / 2, top + row, wb)
                }
            }
        }
        guard part == .features else { return path }
        // The mouth follows the eyes a little. Pixel shapes, not curves: the
        // bar, or a small "u" when Boop smiles.
        let mx = Int((p.lookX * g.lookX * g.mouthFollow).rounded())
        let my = rest + g.mouthRow + Int((p.lookY * g.lookY * g.mouthFollow).rounded())
        if p.smile >= 0.3 {
            fill(mx - 3, my)
            fill(mx + 3, my)
            fill(mx - 2, my + 1, 5)
        } else {
            let wb = odd(g.mouthWide * max(p.mouth, 0.2), least: 3)
            fill(mx - wb / 2, my, wb, 2)
        }
        return path
    }
}

/// The menu-bar icon: Boop's window eyes and a pixel smile, on whole points
/// so it's crisp at 1× and 2×. Closed while asleep, open while agents idle,
/// with a small dot while they work, and amber when something needs you
/// (UX.md §6).
@MainActor
enum MenuBarIcon {
    private static var cache: [FaceMood: NSImage] = [:]

    /// Made once per mood. The coloured ones redraw every time they're
    /// shown, so they follow the menu bar between light and dark.
    static func image(_ mood: FaceMood) -> NSImage {
        if let image = cache[mood] { return image }
        let image = draw(mood)
        cache[mood] = image
        return image
    }

    private static func draw(_ mood: FaceMood) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
            let dark = match == .darkAqua || match == .vibrantDark
            let colour: NSColor = switch mood {
            // The device's amber is too pale on a light bar; a deeper one
            // keeps 3:1 there and still reads as amber.
            case .needsYou: NSColor(hex: dark ? Palette.amber : Palette.menuAmberLight)
            default: .black
            }
            colour.setFill()
            // Window eyes, as on the device: four 2 pt panes around a 1 pt
            // cross, or a bar while asleep.
            for x: CGFloat in [3, 12] {
                if mood == .asleep {
                    NSRect(x: x, y: 8, width: 5, height: 2).fill()
                    continue
                }
                for dx: CGFloat in [0, 3] {
                    for dy: CGFloat in [0, 3] { NSRect(x: x + dx, y: 5 + dy, width: 2, height: 2).fill() }
                }
            }
            // A small pixel "u", as the device draws its smile.
            for r in [NSRect(x: 8, y: 13, width: 1, height: 1), NSRect(x: 11, y: 13, width: 1, height: 1),
                      NSRect(x: 9, y: 14, width: 2, height: 1)] { r.fill() }
            // The dot sits clear of the eye, 2 pt above it.
            if mood == .working || mood == .needsYou {
                NSRect(x: 16, y: 0, width: 3, height: 3).fill()
            }
            return true
        }
        image.isTemplate = mood != .needsYou
        if !image.isTemplate { image.cacheMode = .never }
        image.accessibilityDescription = "Boop"
        return image
    }
}
