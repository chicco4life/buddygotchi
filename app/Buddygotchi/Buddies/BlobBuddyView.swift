import SwiftUI

struct BlobBuddyView: View {
    let petState: PetState
    var size: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glowColor: Color {
        switch petState {
        case .attention: BuddyTheme.amber
        case .celebrate: BuddyTheme.green
        case .error: BuddyTheme.stuckRed
        case .busy, .thinking: BuddyTheme.workGlow
        case .idle, .sleep: BuddyTheme.textSecondary
        }
    }

    private var glowOpacity: Double {
        switch petState {
        case .sleep: 0.08
        case .idle: 0.16
        case .busy, .thinking: 0.28
        case .attention, .error: 0.38
        case .celebrate: 0.42
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 0.1)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : sin(t * 0.9) * 2
            let rock = reduceMotion ? 0 : sin(t * 0.7) * 1.3

            ZStack {
                RadialGradient(
                    colors: [glowColor.opacity(glowOpacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.52
                )
                .frame(width: size * 1.24, height: size * 0.9)
                .blur(radius: 16)

                blobBody
                    .offset(y: CGFloat(bob))
                    .rotationEffect(.degrees(rock))

                face(at: t)
                    .offset(y: CGFloat(bob) - size * 0.03)
                    .rotationEffect(.degrees(rock))

                if petState == .celebrate {
                    twinkles(t)
                }
            }
            .frame(width: size * 1.35, height: size)
        }
        .accessibilityLabel("blob buddy, \(petState.rawValue)")
    }

    private var blobBody: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "#F7F2E9"),
                            BuddyTheme.textPrimary,
                            Color(hex: "#D8CCB9"),
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: size * 0.65
                    )
                )
                .frame(width: size * 0.86, height: size * 0.72)
                .shadow(color: glowColor.opacity(0.35), radius: 16, y: 8)

            Ellipse()
                .fill(BuddyTheme.night.opacity(0.08))
                .frame(width: size * 0.58, height: size * 0.12)
                .offset(y: size * 0.28)
                .blur(radius: 7)
        }
    }

    @ViewBuilder
    private func face(at t: TimeInterval) -> some View {
        let blink = petState == .idle && Int(t * 2.0) % 13 == 0
        let closed = petState == .sleep || blink
        let eyeColor = BuddyTheme.night

        HStack(spacing: size * 0.12) {
            eye(closed: closed, error: petState == .error)
            eye(closed: closed, error: petState == .error)
        }
        .foregroundStyle(eyeColor)
        .overlay(alignment: .bottom) {
            mouth
                .offset(y: size * 0.08)
        }
        .overlay {
            HStack(spacing: size * 0.38) {
                Circle()
                    .fill(BuddyTheme.amber.opacity(0.24))
                    .frame(width: size * 0.09, height: size * 0.06)
                Circle()
                    .fill(BuddyTheme.amber.opacity(0.24))
                    .frame(width: size * 0.09, height: size * 0.06)
            }
            .offset(y: size * 0.08)
        }
        .offset(y: -size * 0.05)
    }

    private func eye(closed: Bool, error: Bool) -> some View {
        Group {
            if error {
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.13, weight: .semibold))
            } else if petState == .celebrate {
                Capsule()
                    .frame(width: size * 0.12, height: size * 0.035)
                    .rotationEffect(.degrees(18))
            } else if closed {
                Capsule()
                    .frame(width: size * 0.12, height: size * 0.025)
            } else {
                Capsule()
                    .frame(width: petState == .busy ? size * 0.09 : size * 0.105,
                           height: petState == .attention ? size * 0.14 : size * 0.105)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch petState {
        case .celebrate:
            Image(systemName: "chevron.down")
                .font(.system(size: size * 0.11, weight: .semibold))
                .foregroundStyle(BuddyTheme.night)
        case .attention:
            Circle()
                .stroke(BuddyTheme.night, lineWidth: 2)
                .frame(width: size * 0.05, height: size * 0.05)
        case .thinking:
            Text("…")
                .font(.system(size: size * 0.09, weight: .semibold, design: .rounded))
                .foregroundStyle(BuddyTheme.night)
        default:
            Capsule()
                .frame(width: size * 0.11, height: 2)
                .foregroundStyle(BuddyTheme.night.opacity(0.8))
        }
    }

    private func twinkles(_ t: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { idx in
                Image(systemName: "sparkle")
                    .font(.system(size: 10 + CGFloat(idx % 2) * 3))
                    .foregroundStyle(BuddyTheme.green)
                    .opacity(reduceMotion ? 0.9 : max(0.25, sin(t * 2.4 + Double(idx)) * 0.45 + 0.55))
                    .offset(
                        x: [-58, 52, -36, 38][idx],
                        y: [-28, -18, 32, 36][idx]
                    )
            }
        }
    }
}
