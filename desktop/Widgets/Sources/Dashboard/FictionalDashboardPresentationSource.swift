import AgentMeterCore
import AgentMeterWidgetCore
import Foundation

enum FictionalDashboardPresentationSource {
    static let nowEpoch = 1_799_900_000
    static let endingDayEpoch = 1_799_884_800

    static let providerEntities: [ProviderEntity] = [
        ProviderEntity(id: "codex", name: "Codex"),
        ProviderEntity(id: "claude", name: "Claude"),
        ProviderEntity(id: "gemini", name: "Gemini"),
        ProviderEntity(id: "cursor", name: "Cursor"),
        ProviderEntity(id: "longname", name: "Aperture Research Allowance Service"),
        ProviderEntity(id: "atlas", name: "Atlas"),
        ProviderEntity(id: "nova", name: "Nova"),
        ProviderEntity(id: "prism", name: "Prism"),
    ]

    static func presentation(
        for intent: DashboardWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetPresentation {
        WidgetPresentationResolver.resolve(
            configuration: IntentConfigurationAdapter.dashboard(intent),
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
        historyStartEpoch: endingDayEpoch - 29 * 86_400,
        providers: [
            provider(
                id: "codex",
                name: "Codex",
                status: "Allowance available",
                windows: [
                    window("weekly", "Weekly", 42, reset: nowEpoch + 120_000),
                    window("session", "Session", 18, reset: nowEpoch + 4_000),
                    window("model", "GPT-5", 27, reset: nil),
                    window("reserve", "Reserve", 11, reset: nowEpoch + 300_000),
                ]
            ),
            provider(
                id: "claude",
                name: "Claude",
                status: "Allowance value unavailable",
                windows: [
                    window("monthly", "Monthly", nil, reset: nil),
                    window("session", "Session", 24, reset: nowEpoch + 3_000),
                    window("opus", "Opus", 58, reset: nil),
                ]
            ),
            provider(
                id: "gemini",
                name: "Gemini",
                status: "Allowance available",
                windows: [
                    window("monthly", "Monthly", 63, reset: nowEpoch + 210_000),
                    window("daily", "Daily", 21, reset: nowEpoch + 9_000),
                    window("pro", "Gemini Pro", 35, reset: nil),
                ]
            ),
            provider(
                id: "cursor",
                name: "Cursor",
                status: "Awaiting refresh",
                windows: [
                    window("billing", "Billing", 9, reset: nowEpoch - 60),
                    window("session", "Session", 4, reset: nowEpoch + 2_000),
                ]
            ),
            provider(
                id: "longname",
                name: "Aperture Research Allowance Service",
                status: "Allowance available",
                windows: [
                    window("monthly", "Monthly", 71, reset: nowEpoch + 410_000),
                    window("daily", "Daily", 38, reset: nowEpoch + 12_000),
                ]
            ),
            provider(
                id: "atlas",
                name: "Atlas",
                status: "Allowance available",
                windows: [
                    window("weekly", "Weekly", 29, reset: nowEpoch + 510_000),
                    window("daily", "Daily", 12, reset: nowEpoch + 14_000),
                ]
            ),
            provider(
                id: "nova",
                name: "Nova",
                status: "Allowance available",
                windows: [
                    window("monthly", "Monthly", 48, reset: nowEpoch + 610_000),
                    window("session", "Session", 31, reset: nowEpoch + 16_000),
                ]
            ),
            provider(
                id: "prism",
                name: "Prism",
                status: "Allowance available",
                windows: [
                    window("weekly", "Weekly", 16, reset: nowEpoch + 710_000),
                    window("daily", "Daily", 7, reset: nowEpoch + 18_000),
                ]
            ),
        ]
    )

    private static func provider(
        id: String,
        name: String,
        status: String,
        windows: [WidgetWindowSnapshot]
    ) -> WidgetProviderSnapshot {
        WidgetProviderSnapshot(
            id: id,
            name: name,
            status: status,
            updatedAtEpoch: nowEpoch - 120,
            windows: windows,
            history: windows.prefix(WidgetSnapshot.maximumHistoryWindowCountPerProvider).flatMap { selectedWindow in
                (0..<30).compactMap { offset -> WidgetHistoryDay? in
                    if offset == 5 || offset == 18 || offset == 26 { return nil }
                    let day = endingDayEpoch - (29 - offset) * 86_400
                    let used = selectedWindow.usedPercent.map {
                        min(100, max(0, $0 - (29 - offset) / 2))
                    }
                    return WidgetHistoryDay(
                        providerId: id,
                        windowKind: selectedWindow.kind,
                        dayStartEpoch: day,
                        consumedPercentPoints: offset == 0 ? 0 : (offset * 3 + id.count) % 41,
                        latestUsedPercent: used,
                        resetAtEpoch: selectedWindow.resetAtEpoch
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
