import AgentMeterWidgetCore
import SwiftUI

enum ResetSummaryContent: Equatable {
    case text(String)
    case timer(Date)
    case absoluteDate(Date)
}

struct ResetSummarySemantics: Equatable {
    let content: [ResetSummaryContent]

    init(
        presentation: WidgetRingPresentation,
        showsCountdown: Bool,
        showsAbsoluteDate: Bool
    ) {
        switch presentation.resetState {
        case .unavailable:
            content = [.text("Reset time unavailable")]
        case .pending:
            content = [.text("Refresh pending")]
        case let .scheduled(epoch):
            let resetDate = Date(timeIntervalSince1970: TimeInterval(epoch))
            var scheduled: [ResetSummaryContent] = []
            if showsCountdown { scheduled.append(.timer(resetDate)) }
            if showsAbsoluteDate { scheduled.append(.absoluteDate(resetDate)) }
            content = scheduled.isEmpty ? [.text("Reset scheduled")] : scheduled
        }
    }

    func accessibilityLines(relativeTo referenceDate: Date) -> [String] {
        content.map { item in
            switch item {
            case let .text(copy):
                copy
            case let .timer(resetDate):
                "Reset countdown \(Self.countdown(from: referenceDate, to: resetDate))"
            case let .absoluteDate(resetDate):
                "Reset date \(resetDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
            }
        }
    }

    private static func countdown(from referenceDate: Date, to resetDate: Date) -> String {
        let seconds = Int(resetDate.timeIntervalSince(referenceDate).rounded())
        let magnitude = abs(seconds)
        let value: Int
        let unit: String

        if magnitude >= 86_400 {
            value = max(1, magnitude / 86_400)
            unit = value == 1 ? "day" : "days"
        } else if magnitude >= 3_600 {
            value = max(1, magnitude / 3_600)
            unit = value == 1 ? "hour" : "hours"
        } else if magnitude >= 60 {
            value = max(1, magnitude / 60)
            unit = value == 1 ? "minute" : "minutes"
        } else {
            value = magnitude
            unit = value == 1 ? "second" : "seconds"
        }

        return seconds >= 0 ? "in \(value) \(unit)" : "\(value) \(unit) ago"
    }
}

struct ResetSummary: View {
    let presentation: WidgetRingPresentation
    let showsCountdown: Bool
    let showsAbsoluteDate: Bool
    var showsLabel = true
    var compact = false

    private var semantics: ResetSummarySemantics {
        ResetSummarySemantics(
            presentation: presentation,
            showsCountdown: showsCountdown,
            showsAbsoluteDate: showsAbsoluteDate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            if showsLabel {
                Text(presentation.label)
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1)
            }

            ForEach(Array(semantics.content.enumerated()), id: \.offset) { _, item in
                contentView(item)
            }
        }
        .font(compact ? .caption2 : .caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func contentView(_ content: ResetSummaryContent) -> some View {
        switch content {
        case let .text(copy):
            if compact {
                Text(copy)
            } else if case .unavailable = presentation.resetState {
                Label(copy, systemImage: "questionmark.circle")
            } else if case .pending = presentation.resetState {
                Label(copy, systemImage: "arrow.clockwise")
            } else {
                Text(copy)
            }
        case let .timer(resetDate):
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(resetDate, style: .timer)
                    .monospacedDigit()
            }
        case let .absoluteDate(resetDate):
            Text(resetDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                .lineLimit(1)
        }
    }
}
