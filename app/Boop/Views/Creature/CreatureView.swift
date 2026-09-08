import SwiftUI

/// Pure expression mapping shared by the desktop face and the status item.
struct CreaturePose: Equatable, Sendable {
    enum Eyes: Equatable, Sendable { case closed, open, down, wide, arc, half }
    var eyes: Eyes
    var eyeOpenness: Double
    var furrow: Bool
    var sweat: Bool
    var tremble: Bool
    var blush: Bool
    var hearts: Bool
    var confetti: Int
    var squish: Bool
    init(from creature: Creature) {
        switch creature.state {
        case .asleep: eyes = .closed
        case .idle: eyes = .open
        case .working: eyes = .down
        case .needsYou: eyes = .wide
        case .done: eyes = .arc
        case .uhoh: eyes = .half
        }
        furrow = creature.state == .working && creature.effort != nil && creature.effort != .light
        eyeOpenness = eyes == .half ? 15 / 33 : eyes == .wide ? 41.5 / 33 : furrow ? 25 / 33 : 1
        sweat = furrow
        tremble = creature.state == .working && creature.effort == .grinding
        let affection = [.idle, .working, .done].contains(creature.state) && creature.overlay != nil
        hearts = affection && (creature.overlay == .boop || creature.greetLevel == 3)
        blush = affection || (creature.state == .done && creature.cheer == .dance)
        squish = affection
        confetti = creature.state == .done ? (creature.cheer == .dance ? 18 : creature.cheer == .cheer ? 9 : 0) : 0
    }
}

struct CreatureView: View {
    var creature: Creature
    var cosmetic = EquippedCosmetic()
    var frozen = false
    var cream = false
    var frozenTime = 1.25
    var grey = false
    var paused = false
    @State private var enteredAt = Date.now
    @Environment(\.snapshotFrozen) private var snapshotFrozen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let pose = CreaturePose(from: creature)
        let field: Color = creature.state == .needsYou ? .orange : creature.state == .uhoh ? .red : tint
        let fieldGradient = Gradient(colors: [field.opacity(creature.state == .needsYou ? 0.35 : 0.12), .clear])
        let bodyGradient = Gradient(colors: [tint.opacity(cream ? 0.65 : 0.18), tint.opacity(cream ? 0.4 : 0.10)])
        let confetti = confettiRing(count: pose.confetti)
        let glyphs = CreatureGlyphs(tint: tint)
        TimelineView(.animation(minimumInterval: creature.animationInterval, paused: paused || frozen || snapshotFrozen || reduceMotion)) { timeline in
            let t = frozen || snapshotFrozen || reduceMotion ? frozenTime : timeline.date.timeIntervalSince(enteredAt)
            Canvas { context, size in
                let texts = glyphs.resolve(in: context)
                draw(&context, size: size, time: t, pose: pose, fieldGradient: fieldGradient, bodyGradient: bodyGradient, confetti: confetti, heart: texts.0, moon: texts.1, more: texts.2)
            }
        }
        .onChange(of: creature.state) { _, _ in enteredAt = .now }
        .onChange(of: creature.overlay) { _, _ in enteredAt = .now }
        .onChange(of: creature.cheer) { _, _ in enteredAt = .now }
        .accessibilityLabel(creature.statusLabel)
        .accessibilityElement(children: .ignore)
    }
    private var tint: Color {
        if grey { return .gray }
        switch cosmetic.skin {
        case "sky": return Color(hex: "91C9E9")
        case "mint": return Color(hex: "9ACCB3")
        case "ember": return Color(hex: "E9A17E")
        case "midnight": return Color(hex: "9692C8")
        default: return Color(hex: "E9CE9B")
        }
    }
    private func draw(_ context: inout GraphicsContext, size: CGSize, time t: Double, pose: CreaturePose, fieldGradient: Gradient, bodyGradient: Gradient, confetti: [(Path, Color)], heart: GraphicsContext.ResolvedText, moon: GraphicsContext.ResolvedText, more: GraphicsContext.ResolvedText) {
        context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24), with: .color(Color(hex: cream ? "F6EEDC" : "171513")))
        let scale = min(size.width / 240, size.height / 200)
        context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 200 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.fill(Path(ellipseIn: CGRect(x: 25, y: 25, width: 190, height: 160)), with: .radialGradient(fieldGradient, center: CGPoint(x: 120, y: 105), startRadius: 20, endRadius: 100))
        if creature.state == .done {
            context.stroke(Path(ellipseIn: CGRect(x: 36, y: 150, width: 168, height: 24)), with: .color(.green.opacity(0.25)), lineWidth: 2)
        }
        let hop = creature.state == .done ? -abs(sin(t * 4)) * Double((creature.cheer ?? .hop).intensity * 5) : sin(t * (creature.state == .asleep ? 0.8 : 1.4)) * 2
        context.translateBy(x: pose.tremble ? sin(t * 37) * 0.75 : 0, y: hop)
        if creature.state == .done || pose.squish {
            context.translateBy(x: 120, y: 110)
            if creature.cheer == .dance { context.rotate(by: .radians(sin(t * 5) * 0.4)) }
            else if creature.state == .done && creature.cheer == .cheer { context.rotate(by: .radians(t.truncatingRemainder(dividingBy: 2.5) / 2.5 * .pi * 2)) }
            if pose.squish { let amount = sin(t * 6) * 0.06; context.scaleBy(x: 1 + amount, y: 1 - amount) }
            context.translateBy(x: -120, y: -110)
        }
        let tall = cosmetic.silhouette == "tall"
        let round = cosmetic.silhouette == "round"
        let body = CGRect(x: tall ? 67 : round ? 52.5 : 46, y: tall ? 39 : 55, width: tall ? 106 : round ? 135 : 148, height: (tall ? 118 : round ? 108 : 96) + sin(t * 0.7) * 1.5)
        context.fill(Path(roundedRect: body, cornerRadius: tall ? 54 : 60), with: .linearGradient(bodyGradient, startPoint: CGPoint(x: 90, y: 60), endPoint: CGPoint(x: 140, y: 170)))
        let ink = grey ? Color.gray : cream ? Color(hex: "66503B") : tint
        let blink = !frozen && !snapshotFrozen && creature.state == .idle && t.truncatingRemainder(dividingBy: 5) < 0.16
        drawEyes(&context, pose: pose, centers: [CGPoint(x: 77.5, y: 103), CGPoint(x: 162.5, y: 103)], scale: 1, ink: ink, blink: blink, gaze: creature.state == .idle ? sin(t * 0.31) * 5.5 : 0)
        var mouth = Path(); mouth.move(to: CGPoint(x: 113, y: 130)); mouth.addQuadCurve(to: CGPoint(x: 127, y: 130), control: CGPoint(x: 120, y: creature.state == .uhoh ? 128 : 139))
        context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        if pose.blush { for x in [76.0, 151.0] { context.fill(Path(ellipseIn: CGRect(x: x, y: 121, width: 15, height: 7)), with: .color(.pink.opacity(0.55))) } }
        if pose.sweat { context.fill(Path(ellipseIn: CGRect(x: 167, y: 88, width: 7, height: 13)), with: .color(.cyan.opacity(0.8))) }
        for (path, color) in confetti { context.fill(path, with: .color(color)) }
        if pose.hearts { for x in [48.0, 190.0] { context.draw(heart, at: CGPoint(x: x, y: 63)) } }
        switch cosmetic.accessory {
        case "sprout":
            context.fill(Path(ellipseIn: CGRect(x: 108, y: body.minY - 12, width: 14, height: 9)), with: .color(.green))
            context.fill(Path(ellipseIn: CGRect(x: 120, y: body.minY - 15, width: 14, height: 9)), with: .color(.green))
        case "scarf": context.fill(Path(roundedRect: CGRect(x: 68, y: 149, width: 104, height: 12), cornerRadius: 6), with: .color(.red.opacity(0.7)))
        case "crown":
            var crown = Path(); crown.move(to: CGPoint(x: 103, y: body.minY)); for p in [CGPoint(x: 100, y: body.minY - 18), CGPoint(x: 112, y: body.minY - 10), CGPoint(x: 120, y: body.minY - 24), CGPoint(x: 128, y: body.minY - 10), CGPoint(x: 140, y: body.minY - 18), CGPoint(x: 137, y: body.minY)] { crown.addLine(to: p) }; crown.closeSubpath(); context.fill(crown, with: .color(.orange))
        default: break
        }
        if creature.focus { context.draw(moon, at: CGPoint(x: 220, y: 20)) }
        if creature.dots > 4 { context.draw(more, at: CGPoint(x: 148, y: 187)) }
        for i in 0..<min(4, creature.dots) { context.fill(Path(ellipseIn: CGRect(x: 103 + i * 10, y: 185, width: 4, height: 4)), with: .color(creature.dotAlert == i ? .red : tint)) }
    }
}

struct MenuBarFace: View {
    var creature: Creature
    var body: some View {
        let pose = CreaturePose(from: creature)
        Canvas { context, _ in
            context.fill(Path(ellipseIn: CGRect(x: 1, y: 3, width: 16, height: 12)), with: .color(.primary))
            drawEyes(&context, pose: pose, centers: [CGPoint(x: 6, y: 8), CGPoint(x: 12, y: 8)], scale: 0.105, ink: Color(nsColor: .windowBackgroundColor))
            if creature.state == .done {
                let depth = Double((creature.cheer ?? .hop).intensity)
                var mouth = Path(); mouth.move(to: CGPoint(x: 7, y: 11)); mouth.addQuadCurve(to: CGPoint(x: 11, y: 11), control: CGPoint(x: 9, y: 11 + depth))
                context.stroke(mouth, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 0.8)
            }
        }.frame(width: 18, height: 18)
    }
}

private struct SnapshotFrozenKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshotFrozen: Bool {
        get { self[SnapshotFrozenKey.self] }
        set { self[SnapshotFrozenKey.self] = newValue }
    }
}

/// Both surfaces use the same eye paths and openness, in creature coordinates.
private func drawEyes(_ context: inout GraphicsContext, pose: CreaturePose, centers: [CGPoint], scale: Double, ink: Color, blink: Bool = false, gaze: Double = 0) {
    for (index, center) in centers.enumerated() {
        var eyeContext = context
        eyeContext.translateBy(x: center.x, y: center.y)
        eyeContext.scaleBy(x: scale, y: scale)
        var eye = Path()
        switch blink ? .closed : pose.eyes {
        case .closed, .arc:
            eye.move(to: CGPoint(x: -13, y: 0))
            eye.addQuadCurve(to: CGPoint(x: 13, y: 0), control: CGPoint(x: 0, y: !blink && pose.eyes == .arc ? -15 : 4))
            eyeContext.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        default:
            let height = 33 * pose.eyeOpenness
            let dx = pose.eyes == .down ? -8.5 : gaze
            eyeContext.fill(Path(roundedRect: CGRect(x: -13.25 + dx, y: -height / 2 + (pose.eyes == .down ? 6 : 0), width: 26.5, height: height), cornerRadius: 9), with: .color(ink))
        }
        if pose.furrow {
            var brow = Path()
            brow.move(to: CGPoint(x: -13, y: -21 + (index == 0 ? 0 : 5)))
            brow.addLine(to: CGPoint(x: 13, y: -21 + (index == 0 ? 5 : 0)))
            eyeContext.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}

extension Creature {
    var animationInterval: Double {
        switch state { case .asleep: 0.5; case .idle: 0.125; default: 1 / 30 }
    }
}

private func confettiRing(count: Int) -> [(Path, Color)] {
    let colors: [Color] = [.green, .pink, .orange]
    return (0..<count).map { i in
        let angle = Double(i) * 2.4
        let rect = CGRect(x: 120 + cos(angle) * 91, y: 85 + sin(angle) * 64, width: 4, height: 7)
        return (Path(rect), colors[i % colors.count])
    }
}

/// A Canvas provides the resolving context. Cache its invariant text resources
/// for the lifetime of this timeline, rather than resolving on every tick.
private final class CreatureGlyphs {
    let tint: Color
    private var texts: (GraphicsContext.ResolvedText, GraphicsContext.ResolvedText, GraphicsContext.ResolvedText)?
    init(tint: Color) { self.tint = tint }
    func resolve(in context: GraphicsContext) -> (GraphicsContext.ResolvedText, GraphicsContext.ResolvedText, GraphicsContext.ResolvedText) {
        if let texts { return texts }
        let resolved = (
            context.resolve(Text("♥").font(.system(size: 17)).foregroundStyle(.pink)),
            context.resolve(Text(Image(systemName: "moon.fill")).foregroundStyle(tint)),
            context.resolve(Text("+").foregroundStyle(tint))
        )
        texts = resolved
        return resolved
    }
}
