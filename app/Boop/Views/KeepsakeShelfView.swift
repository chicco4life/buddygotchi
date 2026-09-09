import SwiftUI

/// The museum: every drawing agents have left, newest first. Deliberately a
/// quiet little gallery — thumbnails, who made it, when — not a dashboard.
/// Milestones as memories (plan doc, P5): this is the shelf they sit on.
struct KeepsakeShelfView: View {
    let engine: BuddyEngine
    @Binding var isPresented: Bool

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: { isPresented = false }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(BuddyTheme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BuddyCopy.shared.settingsCopy.backToLiveView)

                Text(BuddyCopy.shared.popover.keepsakeShelf)
                    .font(.headline)
                    .foregroundStyle(BuddyTheme.ink)

                Spacer(minLength: 8)
            }

            let keepsakes = Array(engine.petMemory.keepsakes.reversed())
            if keepsakes.isEmpty {
                Spacer().frame(height: 24)
                Text(BuddyCopy.shared.popover.keepsakeShelfEmpty)
                    .font(.footnote)
                    .foregroundStyle(BuddyTheme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Spacer().frame(height: 12)
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(Array(keepsakes.enumerated()), id: \.offset) { _, drawing in
                            KeepsakeCell(drawing: drawing)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 320)
            }

            Spacer(minLength: 8)
        }
        .padding(18)
        .frame(width: BuddyTheme.popoverWidth)
        .frame(minHeight: 180)
    }
}

private struct KeepsakeCell: View {
    let drawing: AgentDrawing

    var body: some View {
        VStack(spacing: 4) {
            KeepsakeThumb(drawing: drawing)
                .frame(width: 84, height: 84)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Text(drawing.caption?.isEmpty == false ? drawing.caption! : drawing.agentId)
                .font(.caption)
                .foregroundStyle(BuddyTheme.inkSoft)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(BuddyTheme.inkFaint)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drawing by \(drawing.agentId)\(drawing.caption.map { ": \($0)" } ?? ""), \(subtitle)")
    }

    private var subtitle: String {
        let date = Date(timeIntervalSince1970: drawing.at / 1000)
        let formatted = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(drawing.agentId) · \(formatted)"
    }
}

/// Same chunky renderer as the live card, sized for a shelf thumbnail.
private struct KeepsakeThumb: View {
    let drawing: AgentDrawing

    var body: some View {
        Canvas { context, size in
            let w = max(drawing.width, 1), h = max(drawing.height, 1)
            let cell = min(size.width / CGFloat(w), size.height / CGFloat(h))
            let ox = (size.width - cell * CGFloat(w)) / 2
            let oy = (size.height - cell * CGFloat(h)) / 2
            for (y, row) in drawing.rows.enumerated() {
                for (x, digit) in row.enumerated() {
                    guard let color = drawingPaletteColor(digit) else { continue }
                    let rect = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell,
                                      width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

/// Hex digit → the fixed drawing palette (AgentVocabulary.palette).
/// nil for index 0 (transparent) and anything unparseable.
func drawingPaletteColor(_ digit: Character) -> Color? {
    guard let index = digit.hexDigitValue, index > 0,
          index < AgentVocabulary.palette.count else { return nil }
    let hex = AgentVocabulary.palette[index]
    guard hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
    return Color(
        red: Double((value >> 16) & 0xFF) / 255.0,
        green: Double((value >> 8) & 0xFF) / 255.0,
        blue: Double(value & 0xFF) / 255.0
    )
}
