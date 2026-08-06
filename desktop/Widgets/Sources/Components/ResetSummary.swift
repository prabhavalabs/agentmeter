import AgentMeterWidgetCore
import SwiftUI

struct ResetSummary: View {
    let presentation: WidgetRingPresentation
    let showsCountdown: Bool
    let showsAbsoluteDate: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            Text(presentation.label)
                .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(1)

            switch presentation.resetState {
            case .unavailable:
                if compact {
                    Text("Reset time unavailable")
                } else {
                    Label("Reset time unavailable", systemImage: "questionmark.circle")
                }
            case .pending:
                if compact {
                    Text("Refresh pending")
                } else {
                    Label("Refresh pending", systemImage: "arrow.clockwise")
                }
            case let .scheduled(epoch):
                scheduledReset(epoch: epoch)
            }
        }
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func scheduledReset(epoch: Int) -> some View {
        let resetDate = Date(timeIntervalSince1970: TimeInterval(epoch))
        if showsCountdown {
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(resetDate, style: .timer)
                    .monospacedDigit()
            }
        }
        if showsAbsoluteDate {
            Text(resetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                .lineLimit(1)
        }
        if showsCountdown == false && showsAbsoluteDate == false {
            Text("Reset scheduled")
        }
    }
}
