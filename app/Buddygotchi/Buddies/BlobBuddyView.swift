import SwiftUI

struct BlobBuddyView: View {
    let petState: PetState
    var size: CGFloat = 150

    @State private var stateEntryDate = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let breathePeriod: TimeInterval = 4.0
    private let amberPeriod: TimeInterval = 2.4
    private let heartbeatPeriod: TimeInterval = 2.6
    private let sleepPeekPeriod: TimeInterval = 8.0
    private let rippleDuration: TimeInterval = 0.9
    private let twinkleDuration: TimeInterval = 3.2
    private let thinkingDotsPeriod: TimeInterval = 2.0

    private var stateTickInterval: TimeInterval {
        guard !reduceMotion else { return 60 }
        switch petState {
        case .sleep, .idle:
            return 0.5
        case .busy, .thinking, .attention, .celebrate, .error:
            return 1.0 / 12.0
        }
    }

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
        TimelineView(.periodic(from: stateEntryDate, by: stateTickInterval)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let stateElapsed = max(0, context.date.timeIntervalSince(stateEntryDate))
            let bob = reduceMotion ? 0 : sin(t * 0.9) * 2
            let rock = reduceMotion ? 0 : sin(t * 0.7) * 1.3
            let glowOpacity = animatedGlowOpacity(at: t)
            let glowScale = animatedGlowScale(at: t)

            ZStack {
                RadialGradient(
                    colors: [glowColor.opacity(glowOpacity), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.52
                )
                .frame(width: size * 1.24, height: size * 0.9)
                .blur(radius: 16)
                .scaleEffect(glowScale)

                if petState == .celebrate && !reduceMotion && stateElapsed <= rippleDuration {
                    celebrateRipple(elapsed: stateElapsed)
                }

                blobBody
                    .offset(y: CGFloat(bob))
                    .rotationEffect(.degrees(rock))

                face(at: t)
                    .offset(y: CGFloat(bob) - size * 0.03)
                    .rotationEffect(.degrees(rock))

                if petState == .celebrate && !reduceMotion && stateElapsed <= twinkleDuration {
                    twinkles(elapsed: stateElapsed)
                }
            }
            .frame(width: size * 1.35, height: size)
        }
        .id("\(petState.rawValue)-\(stateTickInterval)")
        .onChange(of: petState) {
            stateEntryDate = Date.now
        }
        .accessibilityLabel("blob buddy, \(petState.rawValue)")
    }

    private func animatedGlowOpacity(at t: TimeInterval) -> Double {
        guard !reduceMotion else { return glowOpacity }

        switch petState {
        case .busy, .thinking:
            return glowOpacity * pulseMultiplier(at: t, period: breathePeriod, minimum: 0.55)
        case .attention:
            return glowOpacity * pulseMultiplier(at: t, period: amberPeriod, minimum: 0.5)
        case .error:
            return heartbeatOpacity(at: t)
        case .celebrate, .idle, .sleep:
            return glowOpacity
        }
    }

    private func animatedGlowScale(at t: TimeInterval) -> CGFloat {
        guard !reduceMotion else { return 1 }
        guard petState == .busy || petState == .thinking else { return 1 }

        let phase = phase(at: t, period: breathePeriod)
        let eased = (1 - cos(phase * 2 * .pi)) / 2
        return 1 + CGFloat(eased) * 0.04
    }

    private func pulseMultiplier(at t: TimeInterval, period: TimeInterval, minimum: Double) -> Double {
        let phase = phase(at: t, period: period)
        let eased = (1 - cos(phase * 2 * .pi)) / 2
        return minimum + (1 - minimum) * eased
    }

    private func heartbeatOpacity(at t: TimeInterval) -> Double {
        let phase = phase(at: t, period: heartbeatPeriod)
        let firstBeat = triangularPulse(phase: phase, center: 0.15, halfWidth: 0.055)
        let secondBeat = triangularPulse(phase: phase, center: 0.30, halfWidth: 0.055)
        return 0.25 + max(firstBeat, secondBeat) * 0.45
    }

    private func triangularPulse(phase: Double, center: Double, halfWidth: Double) -> Double {
        max(0, 1 - abs(phase - center) / halfWidth)
    }

    private func phase(at t: TimeInterval, period: TimeInterval) -> Double {
        let raw = t.truncatingRemainder(dividingBy: period)
        return (raw >= 0 ? raw : raw + period) / period
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
        let blink = !reduceMotion && petState == .idle && Int(t * 2.0) % 13 == 0
        let sleepPeek = !reduceMotion && petState == .sleep && sleepPeekIsOpen(at: t)
        let closed = petState == .sleep || blink
        let eyeColor = BuddyTheme.night

        HStack(spacing: size * 0.12) {
            eye(closed: closed && !sleepPeek, error: petState == .error)
            eye(closed: closed, error: petState == .error)
        }
        .foregroundStyle(eyeColor)
        .overlay(alignment: .bottom) {
            mouth(at: t)
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

    private func sleepPeekIsOpen(at t: TimeInterval) -> Bool {
        let phase = phase(at: t, period: sleepPeekPeriod)
        return phase >= 0.76 && phase <= 0.94
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
                    .frame(width: petState == .busy ? size * 0.085 : size * 0.105,
                           height: petState == .attention ? size * 0.14 : size * 0.105)
            }
        }
    }

    @ViewBuilder
    private func mouth(at t: TimeInterval) -> some View {
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
                .font(.buddy(size * 0.09, weight: .semibold))
                .foregroundStyle(BuddyTheme.night)
                .opacity(reduceMotion ? 1 : pulseMultiplier(at: t, period: thinkingDotsPeriod, minimum: 0.28))
        case .sleep:
            SleepMouthShape()
                .stroke(BuddyTheme.night.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.11, height: size * 0.035)
        default:
            Capsule()
                .frame(width: size * 0.11, height: 2)
                .foregroundStyle(BuddyTheme.night.opacity(0.8))
        }
    }

    private func celebrateRipple(elapsed: TimeInterval) -> some View {
        let progress = min(max(elapsed / rippleDuration, 0), 1)
        return Ellipse()
            .stroke(BuddyTheme.green.opacity(1 - progress), lineWidth: 2)
            .frame(
                width: size * (0.9 + CGFloat(progress) * 0.24),
                height: size * (0.72 + CGFloat(progress) * 0.24)
            )
            .blur(radius: CGFloat(progress) * 1.5)
    }

    private func twinkles(elapsed: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { idx in
                let progress = min(max(elapsed / twinkleDuration, 0), 1)
                let opacity = 0.15 + sin(progress * .pi) * 0.75
                let lift = -4 * sin(progress * .pi)

                Image(systemName: "sparkle")
                    .font(.system(size: 10 + CGFloat(idx % 2) * 3))
                    .foregroundStyle(BuddyTheme.green)
                    .opacity(opacity)
                    .offset(
                        x: [-58, 52, -36, 38][idx],
                        y: [-28, -18, 32, 36][idx] + CGFloat(lift)
                    )
            }
        }
    }
}

private struct SleepMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}
