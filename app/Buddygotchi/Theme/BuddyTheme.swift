import SwiftUI

enum BuddyTheme {
    static let accent = Color(hex: "#9B8AFF")
    static let accentSubtle = Color(hex: "#9B8AFF").opacity(0.15)

    static let connected = accent
    static let disconnected = Color.secondary.opacity(0.5)
    static let attentionAmber = Color(hex: "#FFBB33")
    static let destructive = Color(hex: "#FF6B6B")

    static let cardFill = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.12)
    static let cardFillElevated = Color.white.opacity(0.09)
    static let cardStrokeElevated = Color.white.opacity(0.14)

    static let cardCornerRadius: CGFloat = 10

    static let popoverWidth: CGFloat = 320
    static let liveViewHeight: CGFloat = 240
    static let liveViewExpandedHeight: CGFloat = 380
    static let fullPanelHeight: CGFloat = 440
}

// MARK: - Card Modifiers

struct BuddyCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .fill(elevated ? BuddyTheme.cardFillElevated : BuddyTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                            .strokeBorder(
                                elevated ? BuddyTheme.cardStrokeElevated : BuddyTheme.cardStroke,
                                lineWidth: 0.5
                            )
                    )
            )
    }
}

extension View {
    func buddyCard(elevated: Bool = false) -> some View {
        modifier(BuddyCardModifier(elevated: elevated))
    }
}

// MARK: - Grouped Card (multiple items with internal dividers)

struct BuddyGroupedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                    .fill(BuddyTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: BuddyTheme.cardCornerRadius)
                            .strokeBorder(BuddyTheme.cardStroke, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func buddyGroupedCard() -> some View {
        modifier(BuddyGroupedCardModifier())
    }
}

// MARK: - Button Styles

struct BuddyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                BuddyTheme.accent.opacity(configuration.isPressed ? 0.7 : 1.0),
                in: Capsule()
            )
            .foregroundStyle(.white)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BuddySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded, weight: .medium))
            .foregroundStyle(configuration.isPressed ? .primary : .secondary)
    }
}

// MARK: - Section Header

struct BuddySectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Species Color Helper

func buddySpeciesColor(for species: String) -> Color {
    let buddy = allBuddies[species] ?? allBuddies.values.first!
    return Color(hex: buddy.color)
}
