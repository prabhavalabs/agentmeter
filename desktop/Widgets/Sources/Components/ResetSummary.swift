import AgentMeterWidgetCore
import Foundation
import SwiftUI

enum ResetSummaryContent: Equatable {
    /// Under 24 hours away and countdowns are enabled — the view renders a
    /// live-updating "Resets in …" line.
    case liveRelative(Date)
    /// Deterministic copy from WidgetResetPhrasing.
    case text(String)
}

/// Deterministic reset copy derived from the v2 distance-classified phrasing.
/// All static text comes from WidgetResetPhrasing so views, accessibility, and
/// tests agree on the wording.
struct ResetSummarySemantics: Equatable {
    let phrase: WidgetResetPhrase
    let content: [ResetSummaryContent]
    let nowEpoch: Int

    init(
        presentation: WidgetRingPresentation,
        showsCountdown: Bool,
        showsAbsoluteDate: Bool,
        nowEpoch: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.nowEpoch = nowEpoch
        let phrase = WidgetResetPhrasing.phrase(
            for: presentation.resetState,
            nowEpoch: nowEpoch
        )
        self.phrase = phrase
        switch phrase {
        case let .relative(epoch) where showsCountdown:
            content = [.liveRelative(Date(timeIntervalSince1970: TimeInterval(epoch)))]
        case .relative, .weekdayTime, .calendarDate, .pending, .unavailable:
            content = [.text(WidgetResetPhrasing.longText(phrase, nowEpoch: nowEpoch))]
        }
        // showsAbsoluteDate is retained for call-site compatibility; the long
        // forms already include the absolute date beyond 24 hours.
        _ = showsAbsoluteDate
    }

    var compactText: String {
        WidgetResetPhrasing.compactText(phrase, nowEpoch: nowEpoch)
    }

    func accessibilityLines(relativeTo referenceDate: Date) -> [String] {
        [WidgetResetPhrasing.longText(
            phrase,
            nowEpoch: Int(referenceDate.timeIntervalSince1970)
        )]
    }
}

struct ResetSummary: View {
    let presentation: WidgetRingPresentation
    let semantics: ResetSummarySemantics
    var showsLabel = true
    var compact = false

    init(
        presentation: WidgetRingPresentation,
        showsCountdown: Bool,
        showsAbsoluteDate: Bool,
        showsLabel: Bool = true,
        compact: Bool = false,
        nowEpoch: Int = Int(Date().timeIntervalSince1970)
    ) {
        self.presentation = presentation
        semantics = ResetSummarySemantics(
            presentation: presentation,
            showsCountdown: showsCountdown,
            showsAbsoluteDate: showsAbsoluteDate,
            nowEpoch: nowEpoch
        )
        self.showsLabel = showsLabel
        self.compact = compact
    }

    init(
        presentation: WidgetRingPresentation,
        semantics: ResetSummarySemantics,
        showsLabel: Bool = true,
        compact: Bool = false
    ) {
        self.presentation = presentation
        self.semantics = semantics
        self.showsLabel = showsLabel
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            if showsLabel {
                Text(presentation.label)
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1)
            }

            if compact {
                Text(semantics.compactText)
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                ForEach(Array(semantics.content.enumerated()), id: \.offset) { _, item in
                    contentView(item)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func contentView(_ content: ResetSummaryContent) -> some View {
        switch content {
        case let .liveRelative(resetDate):
            Text("Resets in \(Text(resetDate, style: .relative))")
                .monospacedDigit()
                .lineLimit(1)
        case let .text(copy):
            switch semantics.phrase {
            case .pending:
                Label(copy, systemImage: "arrow.clockwise")
                    .lineLimit(1)
            case .unavailable:
                Label(copy, systemImage: "questionmark.circle")
                    .lineLimit(1)
            case .relative, .weekdayTime, .calendarDate:
                Text(copy)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    private var accessibilitySummary: String {
        let lines = semantics.accessibilityLines(
            relativeTo: Date(timeIntervalSince1970: TimeInterval(semantics.nowEpoch))
        )
        guard showsLabel else { return lines.joined(separator: ", ") }
        return ([presentation.label] + lines).joined(separator: ", ")
    }
}
