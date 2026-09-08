import SwiftUI

/// Pure expression mapping shared by the desktop face and the status item.
struct CreaturePose: Equatable, Sendable {
    enum Eyes: Equatable, Sendable { case closed, open, down, wide, arc, half }
    var eyes: Eyes
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
    var grey = false
    var wakeProgress: Double? = nil
    @State private var enteredAt = Date.now
    @Environment(\.snapshotFrozen) private var snapshotFrozen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: frozen || snapshotFrozen || reduceMotion)) { timeline in
            let t = frozen || snapshotFrozen || reduceMotion ? 1.25 : timeline.date.timeIntervalSince(enteredAt)
            Canvas { context, size in draw(&context, size: size, time: t) }
        }
        .onChange(of: creature.state) { _, _ in enteredAt = .now }
        .onChange(of: creature.overlay) { _, _ in enteredAt = .now }
        .onChange(of: creature.cheer) { _, _ in enteredAt = .now }
        .accessibilityLabel(BuddyCopy.phase7(creature.state.rawValue))
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
    private func draw(_ context: inout GraphicsContext, size: CGSize, time t: Double) {
        let pose = CreaturePose(from: creature)
        context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 24), with: .color(Color(hex: "171513")))
        let scale = min(size.width / 240, size.height / 200)
        context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 200 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let field: Color = creature.state == .needsYou ? .orange : creature.state == .uhoh ? .red : tint
        context.fill(Path(ellipseIn: CGRect(x: 25, y: 25, width: 190, height: 160)), with: .radialGradient(Gradient(colors: [field.opacity(creature.state == .needsYou ? 0.35 : 0.12), .clear]), center: CGPoint(x: 120, y: 105), startRadius: 20, endRadius: 100))
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
        context.fill(Path(roundedRect: body, cornerRadius: tall ? 54 : 60), with: .linearGradient(Gradient(colors: [tint.opacity(0.18), tint.opacity(0.10)]), startPoint: CGPoint(x: 90, y: 60), endPoint: CGPoint(x: 140, y: 170)))
        let ink = grey ? Color.gray : tint
        let blink = !frozen && !snapshotFrozen && creature.state == .idle && t.truncatingRemainder(dividingBy: 5) < 0.16
        for x in [77.5, 162.5] {
            var eye = Path()
            let y = 103.0
            let wakingClosed = wakeProgress.map { $0 < 1.2 || ($0 < 2.2 && x > 120) || (2.6..<2.72).contains($0) || (2.92..<3.04).contains($0) } ?? false
            switch blink || wakingClosed ? CreaturePose.Eyes.closed : pose.eyes {
            case .closed: eye.move(to: CGPoint(x: x - 13, y: y)); eye.addQuadCurve(to: CGPoint(x: x + 13, y: y), control: CGPoint(x: x, y: y + 4))
            case .arc: eye.move(to: CGPoint(x: x - 13, y: y)); eye.addQuadCurve(to: CGPoint(x: x + 13, y: y), control: CGPoint(x: x, y: y - 15))
            default:
                let h = (wakeProgress.map { (3.2..<4).contains($0) } ?? false) ? 41.5 : pose.eyes == .half ? 15.0 : pose.eyes == .wide ? 41.5 : pose.furrow ? 25.0 : 33.0
                let dx = (wakeProgress ?? 0) >= 4 ? 14.0 : pose.eyes == .down ? -8.5 : creature.state == .idle ? sin(t * 0.31) * 5.5 : 0
                context.fill(Path(roundedRect: CGRect(x: x - 13.25 + dx, y: y - h / 2 + (pose.eyes == .down ? 6 : 0), width: 26.5, height: h), cornerRadius: 9), with: .color(ink))
            }
            context.stroke(eye, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            if pose.furrow {
                var brow = Path(); brow.move(to: CGPoint(x: x - 13, y: 82 + (x < 120 ? 0 : 5))); brow.addLine(to: CGPoint(x: x + 13, y: 82 + (x < 120 ? 5 : 0)))
                context.stroke(brow, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        var mouth = Path(); mouth.move(to: CGPoint(x: 113, y: 130)); mouth.addQuadCurve(to: CGPoint(x: 127, y: 130), control: CGPoint(x: 120, y: creature.state == .uhoh ? 128 : 139))
        context.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        if pose.blush { for x in [76.0, 151.0] { context.fill(Path(ellipseIn: CGRect(x: x, y: 121, width: 15, height: 7)), with: .color(.pink.opacity(0.55))) } }
        if pose.sweat { context.fill(Path(ellipseIn: CGRect(x: 167, y: 88, width: 7, height: 13)), with: .color(.cyan.opacity(0.8))) }
        for i in 0..<pose.confetti {
            let a = Double(i) * 2.4
            context.fill(Path(CGRect(x: 120 + cos(a) * 91, y: 85 + sin(a) * 64, width: 4, height: 7)), with: .color([Color.green, .pink, .orange][i % 3]))
        }
        if pose.hearts { for x in [48.0, 190.0] { context.draw(Text("♥").font(.system(size: 17)).foregroundStyle(.pink), at: CGPoint(x: x, y: 63)) } }
        switch cosmetic.accessory {
        case "sprout":
            context.fill(Path(ellipseIn: CGRect(x: 108, y: body.minY - 12, width: 14, height: 9)), with: .color(.green))
            context.fill(Path(ellipseIn: CGRect(x: 120, y: body.minY - 15, width: 14, height: 9)), with: .color(.green))
        case "scarf": context.fill(Path(roundedRect: CGRect(x: 68, y: 149, width: 104, height: 12), cornerRadius: 6), with: .color(.red.opacity(0.7)))
        case "crown":
            var crown = Path(); crown.move(to: CGPoint(x: 103, y: body.minY)); for p in [CGPoint(x: 100, y: body.minY - 18), CGPoint(x: 112, y: body.minY - 10), CGPoint(x: 120, y: body.minY - 24), CGPoint(x: 128, y: body.minY - 10), CGPoint(x: 140, y: body.minY - 18), CGPoint(x: 137, y: body.minY)] { crown.addLine(to: p) }; crown.closeSubpath(); context.fill(crown, with: .color(.orange))
        default: break
        }
        if creature.focus { context.draw(Text(Image(systemName: "moon.fill")).foregroundStyle(tint), at: CGPoint(x: 220, y: 20)) }
        if creature.dots > 4 { context.draw(Text("+").foregroundStyle(tint), at: CGPoint(x: 148, y: 187)) }
        for i in 0..<min(4, creature.dots) { context.fill(Path(ellipseIn: CGRect(x: 103 + i * 10, y: 185, width: 4, height: 4)), with: .color(creature.dotAlert == i ? .red : tint)) }
    }
}

struct MenuBarFace: View {
    var creature: Creature
    var body: some View {
        Canvas { context, _ in
            let pose = CreaturePose(from: creature)
            context.fill(Path(ellipseIn: CGRect(x: 1, y: 3, width: 16, height: 12)), with: .color(.primary))
            for x in [6.0, 12.0] {
                if pose.eyes == .closed || pose.eyes == .arc {
                    var eye = Path(); eye.move(to: CGPoint(x: x - 1.5, y: 8)); eye.addQuadCurve(to: CGPoint(x: x + 1.5, y: 8), control: CGPoint(x: x, y: pose.eyes == .arc ? 5 : 9))
                    context.stroke(eye, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
                } else {
                    let height = pose.eyes == .wide ? 5.0 : pose.eyes == .half ? 1.5 : 3.5
                    context.fill(Path(roundedRect: CGRect(x: x - 1, y: pose.eyes == .down ? 8 : 6, width: 2, height: height), cornerRadius: 1), with: .color(Color(nsColor: .windowBackgroundColor)))
                }
            }
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
