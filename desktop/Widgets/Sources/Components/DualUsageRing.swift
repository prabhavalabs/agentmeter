import AgentMeterWidgetCore
import SwiftUI

struct DualUsageRing: View {
    let outer: WidgetRingPresentation
    let inner: WidgetRingPresentation?
    let accent: Color
    let percentageMode: WidgetPercentageMode
    var track: Color = Color.secondary.opacity(0.18)

    var body: some View {
        ZStack {
            ring(for: outer, lineWidth: 9, color: accent)

            if let inner {
                ring(for: inner, lineWidth: 7, color: accent.opacity(0.62))
                    .padding(15)
            }

            VStack(spacing: 0) {
                ViewThatFits(in: .vertical) {
                    fullLegend
                    compactLegend
                }
            }
            .padding(23)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    @ViewBuilder
    private func ring(
        for presentation: WidgetRingPresentation,
        lineWidth: CGFloat,
        color: Color
    ) -> some View {
        Circle()
            .stroke(track, style: StrokeStyle(lineWidth: lineWidth))

        if let displayedPercent = presentation.displayedPercent {
            Circle()
                .trim(from: 0, to: drawingProgress(displayedPercent))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        } else {
            Circle()
                .stroke(
                    color.opacity(0.55),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2, 5])
                )
        }
    }

    private func drawingProgress(_ percent: Int) -> Double {
        Double(min(max(percent, 0), 100)) / 100
    }

    private func displayText(for presentation: WidgetRingPresentation) -> String {
        presentation.displayedPercent.map { "\($0)%" } ?? "Not reported"
    }

    private var fullLegend: some View {
        VStack(spacing: 0) {
            Text(outer.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(displayText(for: outer))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
            Text(percentageMode == .used ? "used" : "remaining")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let inner {
                Divider()
                    .frame(width: 34)
                Text(DualUsageRingLegend.innerText(inner))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .minimumScaleFactor(0.55)
    }

    private var compactLegend: some View {
        VStack(spacing: 0) {
            Text(displayText(for: outer))
                .font(.system(.body, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
            if let inner {
                Text(DualUsageRingLegend.innerText(inner))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var accessibilitySummary: String {
        ([outer] + [inner].compactMap { $0 }).map { presentation in
            let value = presentation.displayedPercent.map { "\($0) percent" } ?? "Not reported"
            return "\(presentation.label), \(value) \(percentageMode == .used ? "used" : "remaining"), \(resetDescription(presentation.resetState))"
        }.joined(separator: "; ")
    }

    private func resetDescription(_ state: WidgetResetState) -> String {
        switch state {
        case .unavailable: "Reset time unavailable"
        case .scheduled: "Reset scheduled"
        case .pending: "Refresh pending"
        }
    }
}

enum DualUsageRingLegend {
    static func innerText(_ presentation: WidgetRingPresentation) -> String {
        let value = presentation.displayedPercent.map { "\($0)%" } ?? "Not reported"
        return "\(presentation.label) \(value)"
    }
}
