import SwiftUI

/// Horizontal usage track from the v2 design language. Percent 0 keeps a
/// 1.5% sliver visible; a nil percent renders a hatched track — never a
/// zero-width fill.
struct UsageTrackCapsule: View {
    let displayedPercent: Int?
    let accent: Color
    let palette: WidgetThemePalette
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            if let percent = displayedPercent {
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(accent)
                        .frame(width: proxy.size.width * fillFraction(for: percent))
                }
            } else {
                hatchedTrack
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func fillFraction(for percent: Int) -> CGFloat {
        let clamped = min(max(percent, 0), 100)
        guard clamped > 0 else { return 0.015 }
        return CGFloat(clamped) / 100
    }

    private var hatchedTrack: some View {
        Capsule()
            .fill(palette.track.opacity(0.6))
            .overlay(
                Canvas { context, size in
                    var stripes = Path()
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        stripes.move(to: CGPoint(x: x, y: size.height))
                        stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += 6
                    }
                    context.stroke(
                        stripes,
                        with: .color(.white.opacity(0.055)),
                        lineWidth: 1
                    )
                }
                .clipShape(Capsule())
            )
    }
}

/// Labelled usage bar row: label / value line, track, optional reset line.
/// A nil percent renders "Not reported" — never zero.
struct UsageBarRow: View {
    let label: String
    let displayedPercent: Int?
    let accent: Color
    let palette: WidgetThemePalette
    var labelSize: CGFloat = 10
    var valueSize: CGFloat = 10.5
    var trackHeight: CGFloat = 3
    var resetText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let percent = displayedPercent {
                    Text("\(percent)%")
                        .font(.system(size: valueSize, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.primaryText)
                } else {
                    Text("Not reported")
                        .font(.system(size: valueSize, weight: .medium))
                        .foregroundStyle(palette.secondaryText)
                }
            }

            UsageTrackCapsule(
                displayedPercent: displayedPercent,
                accent: accent,
                palette: palette,
                height: trackHeight
            )

            if let resetText {
                Text(resetText)
                    .font(.system(size: max(labelSize - 1, 7)))
                    .monospacedDigit()
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
