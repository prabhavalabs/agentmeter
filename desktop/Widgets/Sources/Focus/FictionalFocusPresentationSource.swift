import AgentMeterCore
import AgentMeterWidgetCore
import Foundation

enum FictionalFocusPresentationSource {
    static let nowEpoch = 1_799_900_000
    static let endingDayEpoch = 1_799_884_800

    static func presentation(
        for intent: FocusWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetPresentation {
        WidgetPresentationResolver.resolve(
            configuration: IntentConfigurationAdapter.focus(intent),
            snapshot: snapshot,
            family: family,
            nowEpoch: nowEpoch,
            endingAtDayEpoch: endingDayEpoch,
            calendar: utcCalendar
        )
    }

    private static let snapshot = WidgetSnapshot(
        generatedAtEpoch: nowEpoch - 120,
        pollIntervalSeconds: 300,
        historyStartEpoch: endingDayEpoch - 6 * 86_400,
        providers: [
            provider(
                id: "codex",
                name: "Codex",
                windows: [
                    window("weekly", "Weekly", 42, reset: nowEpoch + 120_000),
                    window("session", "Session", 18, reset: nowEpoch + 4_000),
                    window("model", "GPT-5", 27, reset: nil),
                ]
            ),
            provider(
                id: "claude",
                name: "Claude",
                windows: [
                    window("monthly", "Monthly", 33, reset: nowEpoch + 200_000),
                    window("session", "Session", 24, reset: nowEpoch + 3_000),
                    window("opus", "Opus", nil, reset: nil),
                ]
            ),
            provider(
                id: "gemini",
                name: "Gemini",
                windows: [
                    window("monthly", "Monthly", 63, reset: nowEpoch + 210_000),
                    window("daily", "Daily", 21, reset: nowEpoch + 9_000),
                    window("pro", "Gemini Pro", 35, reset: nil),
                ]
            ),
            provider(
                id: "cursor",
                name: "Cursor",
                windows: [
                    window("billing", "Billing", 9, reset: nowEpoch + 300_000),
                    window("session", "Session", 4, reset: nowEpoch + 2_000),
                ]
            ),
        ]
    )

    private static func provider(
        id: String,
        name: String,
        windows: [WidgetWindowSnapshot]
    ) -> WidgetProviderSnapshot {
        WidgetProviderSnapshot(
            id: id,
            name: name,
            status: "Fictional allowance data",
            updatedAtEpoch: nowEpoch - 120,
            windows: windows,
            history: windows.prefix(WidgetSnapshot.maximumHistoryWindowCountPerProvider).flatMap { window in
                (0..<7).compactMap { offset -> WidgetHistoryDay? in
                    if offset == 2 { return nil }
                    let day = endingDayEpoch - (6 - offset) * 86_400
                    let latest = min(100, max(0, (window.usedPercent ?? 12) - (6 - offset) * 3))
                    return WidgetHistoryDay(
                        providerId: id,
                        windowKind: window.kind,
                        dayStartEpoch: day,
                        consumedPercentPoints: offset == 0 ? 0 : offset * 4,
                        latestUsedPercent: latest,
                        resetAtEpoch: window.resetAtEpoch
                    )
                }
            }
        )
    }

    private static func window(
        _ kind: String,
        _ label: String,
        _ usedPercent: Int?,
        reset: Int?
    ) -> WidgetWindowSnapshot {
        WidgetWindowSnapshot(
            kind: kind,
            label: label,
            usedPercent: usedPercent,
            resetAtEpoch: reset
        )
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
