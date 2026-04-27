import SwiftUI

struct PetStageView: View {
    let petState: PetState
    let species: String
    var fontSize: CGFloat = 17

    @State private var startDate = Date.now
    @State private var petScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var buddy: BuddySpecies {
        allBuddies[species] ?? allBuddies.values.first!
    }

    private var speciesColor: Color {
        Color(hex: buddy.color)
    }

    private var glowIntensity: CGFloat {
        switch petState {
        case .sleep: 0.03
        case .idle: 0.06
        case .busy: 0.10
        case .attention: 0.14
        case .celebrate: 0.18
        }
    }

    private var shadowRadius: CGFloat {
        switch petState {
        case .sleep: 4
        case .idle: 6
        case .busy: 8
        case .attention: 10
        case .celebrate: 12
        }
    }

    private var shadowOpacity: CGFloat {
        switch petState {
        case .sleep: 0.2
        case .idle: 0.35
        case .busy: 0.45
        case .attention: 0.5
        case .celebrate: 0.55
        }
    }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [speciesColor.opacity(glowIntensity), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 60
            )
            .frame(width: 140, height: 90)
            .blur(radius: 15)

            TimelineView(.periodic(from: startDate, by: 0.2)) { context in
                let tickMs = Int(context.date.timeIntervalSince(startDate) * 1000)
                let frame = renderFrame(buddy: buddy, state: petState.rawValue, tickMs: tickMs)

                Text(frame)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(speciesColor)
                    .shadow(color: speciesColor.opacity(shadowOpacity), radius: shadowRadius)
            }
        }
        .scaleEffect(petScale)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .onChange(of: petState) {
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                petScale = 1.06
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    petScale = 1.0
                }
            }
        }
        .accessibilityLabel("\(species) buddy, \(petState.rawValue)")
    }
}
