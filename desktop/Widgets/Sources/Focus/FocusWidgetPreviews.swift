import AgentMeterWidgetCore
import SwiftUI
import WidgetKit

enum FictionalFocusPresentations {
    static func codex(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
        presentation(
            family: family,
            providerID: "codex",
            providerName: "Codex",
            status: "Ready",
            outer: ring("weekly", "Weekly", 42, reset: .scheduled(epoch: 1_800_000_000)),
            inner: ring("session", "Session", 18, reset: .scheduled(epoch: 1_799_920_000)),
            additional: [],
            theme: .providerTinted,
            historyStyle: .heatMap,
            history: heatMapHistory,
            freshness: .fresh
        )
    }

    static func claude(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
        presentation(
            family: family,
            providerID: "claude",
            providerName: "Claude",
            status: "Waiting for refresh",
            outer: ring("monthly", "Monthly", nil, reset: .unavailable),
            inner: ring("session", "Session", 76, reset: .pending),
            additional: [ring("opus", "Opus", 58, reset: .scheduled(epoch: 1_800_100_000))],
            theme: .neutral,
            historyStyle: .heatMap,
            history: WidgetHistoryProjection(
                availabilityMessage: WidgetPresentationResolver.unavailableHistoryMessage
            ),
            freshness: .stale
        )
    }

    static func gemini(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
        presentation(
            family: family,
            providerID: "gemini",
            providerName: "Gemini",
            status: "Ready",
            outer: ring("monthly", "Monthly", 63, reset: .scheduled(epoch: 1_800_200_000)),
            inner: ring("daily", "Daily", 21, reset: .scheduled(epoch: 1_799_980_000)),
            additional: [ring("pro", "Gemini Pro", 35, reset: .unavailable)],
            theme: .midnight,
            historyStyle: .trend,
            history: trendHistory,
            freshness: .fresh
        )
    }

    static func cursor(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
        presentation(
            family: family,
            providerID: "cursor",
            providerName: "Cursor",
            status: "Ready",
            outer: ring("billing", "Billing", 9, reset: .scheduled(epoch: 1_800_300_000)),
            inner: nil,
            additional: [],
            theme: .system,
            historyStyle: .heatMap,
            history: heatMapHistory,
            freshness: .fresh
        )
    }

    private static func presentation(
        family: AgentMeterWidgetCore.WidgetFamily,
        providerID: String,
        providerName: String,
        status: String,
        outer: WidgetRingPresentation,
        inner: WidgetRingPresentation?,
        additional: [WidgetRingPresentation],
        theme: WidgetTheme,
        historyStyle: WidgetHistoryStyle,
        history: WidgetHistoryProjection,
        freshness: WidgetFreshnessState
    ) -> WidgetPresentation {
        let configuration = WidgetRenderConfiguration(
            kind: .focus,
            providerIDs: [providerID],
            focusProviderID: providerID,
            outerWindowKind: outer.windowKind,
            innerWindowKind: inner?.windowKind,
            percentageMode: .used,
            modules: [.usage, .primaryReset, .history, .status, .freshness],
            historyStyle: historyStyle,
            historyPeriod: .days7,
            heatMapScope: .singleProvider,
            trendWindow: .outer,
            layout: .automatic,
            density: .comfortable,
            theme: theme,
            tapDestination: .providerDetail,
            showsResetCountdown: true,
            showsAbsoluteResetDate: family == .large || family == .extraLarge
        )
        return WidgetPresentation(
            configuration: configuration,
            family: family,
            providers: [
                WidgetProviderPresentation(
                    id: providerID,
                    name: providerName,
                    status: status,
                    rings: [outer] + [inner].compactMap { $0 },
                    additionalWindows: additional
                ),
            ],
            modules: configuration.modules,
            history: history,
            freshness: freshness,
            overflowCount: 0
        )
    }

    private static func ring(
        _ kind: String,
        _ label: String,
        _ percent: Int?,
        reset: WidgetResetState
    ) -> WidgetRingPresentation {
        WidgetRingPresentation(
            windowKind: kind,
            label: label,
            usedPercent: percent,
            displayedPercent: percent,
            resetState: reset
        )
    }

    private static let heatMapHistory = WidgetHistoryProjection(
        cells: [
            WidgetHeatMapCell(dayStartEpoch: 1_799_366_400, value: nil, band: nil),
            WidgetHeatMapCell(dayStartEpoch: 1_799_452_800, value: 0, band: .zero),
            WidgetHeatMapCell(dayStartEpoch: 1_799_539_200, value: 3, band: .low),
            WidgetHeatMapCell(dayStartEpoch: 1_799_625_600, value: 12, band: .moderate),
            WidgetHeatMapCell(dayStartEpoch: 1_799_712_000, value: nil, band: nil),
            WidgetHeatMapCell(dayStartEpoch: 1_799_798_400, value: 22, band: .high),
            WidgetHeatMapCell(dayStartEpoch: 1_799_884_800, value: 37, band: .veryHigh),
        ],
        windowKind: "weekly",
        windowLabel: "Weekly"
    )

    private static let trendHistory = WidgetHistoryProjection(
        trendPoints: [
            WidgetTrendPoint(dayStartEpoch: 1_799_366_400, latestUsedPercent: 8),
            WidgetTrendPoint(dayStartEpoch: 1_799_452_800, latestUsedPercent: 14),
            WidgetTrendPoint(dayStartEpoch: 1_799_539_200, latestUsedPercent: nil),
            WidgetTrendPoint(dayStartEpoch: 1_799_625_600, latestUsedPercent: 36),
            WidgetTrendPoint(dayStartEpoch: 1_799_712_000, latestUsedPercent: 45),
            WidgetTrendPoint(dayStartEpoch: 1_799_798_400, latestUsedPercent: nil),
            WidgetTrendPoint(dayStartEpoch: 1_799_884_800, latestUsedPercent: 63),
        ],
        windowKind: "monthly",
        windowLabel: "Monthly"
    )
}

#Preview("Codex — Small", as: .systemSmall) {
    AgentMeterFocusWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: 1_799_884_800),
        focusPresentation: FictionalFocusPresentations.codex(family: .small)
    )
}

#Preview("Claude — Medium", as: .systemMedium) {
    AgentMeterFocusWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: 1_799_884_800),
        focusPresentation: FictionalFocusPresentations.claude(family: .medium)
    )
}

#Preview("Gemini — Large", as: .systemLarge) {
    AgentMeterFocusWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: 1_799_884_800),
        focusPresentation: FictionalFocusPresentations.gemini(family: .large)
    )
}

#Preview("Cursor — Extra Large", as: .systemExtraLarge) {
    AgentMeterFocusWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: 1_799_884_800),
        focusPresentation: FictionalFocusPresentations.cursor(family: .extraLarge)
    )
}

#Preview("Claude Stale History — Large", as: .systemLarge) {
    AgentMeterFocusWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: 1_799_884_800),
        focusPresentation: FictionalFocusPresentations.claude(family: .large)
    )
}

#Preview("Claude Stale History — Extra Large", as: .systemExtraLarge) {
    AgentMeterFocusWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: 1_799_884_800),
        focusPresentation: FictionalFocusPresentations.claude(family: .extraLarge)
    )
}
