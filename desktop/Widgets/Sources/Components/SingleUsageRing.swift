import SwiftUI

/// Single progress ring from the v2 design language. A nil percent renders as
/// a dashed track — never as zero progress.
struct SingleUsageRing<Center: View>: View {
    let displayedPercent: Int?
    let accent: Color
    let track: Color
    var lineWidth: CGFloat = 7
    var glows = false
    @ViewBuilder let center: () -> Center

    var body: some View {
        ZStack {
            if let percent = displayedPercent {
                Circle()
                    .stroke(track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: glows ? accent.opacity(0.35) : .clear,
                        radius: glows ? 3 : 0
                    )
            } else {
                Circle()
                    .stroke(track, style: StrokeStyle(lineWidth: lineWidth, dash: [3, 5]))
            }
            center()
        }
        .padding(lineWidth / 2)
    }
}
