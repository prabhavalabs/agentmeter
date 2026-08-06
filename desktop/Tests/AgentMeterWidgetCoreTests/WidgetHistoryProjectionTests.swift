import AgentMeterCore
import Foundation
import Testing
@testable import AgentMeterWidgetCore

@Test func heatMapBandsExactBoundariesAndKeepsMissingDaysAsGaps() {
    let end = 10 * 86_400
    let provider = historyProvider(
        id: "codex",
        values: [
            (end - 6 * 86_400, 0),
            (end - 5 * 86_400, 1),
            (end - 4 * 86_400, 5),
            (end - 3 * 86_400, 6),
            (end - 2 * 86_400, 15),
            (end - 86_400, 30),
            (end, 31),
        ]
    )

    let cells = WidgetHistoryProjection.heatMap(
        providers: [provider],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(cells.map(\.band) == [.zero, .low, .low, .moderate, .moderate, .high, .veryHigh])
    #expect(cells.allSatisfy { $0.hasData })

    let withGap = WidgetHistoryProjection.heatMap(
        providers: [historyProvider(id: "codex", values: [(end, 0)])],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )
    #expect(withGap.count == 7)
    #expect(withGap.dropLast().allSatisfy { $0.band == nil && $0.hasData == false })
    #expect(withGap.last?.band == .zero)
}

@Test func heatMapClipsToRequestedInclusivePeriod() {
    let end = 40 * 86_400
    let values = (0..<35).map { (end - $0 * 86_400, $0 + 1) }
    let provider = historyProvider(id: "codex", values: values)

    let seven = WidgetHistoryProjection.heatMap(
        providers: [provider],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )
    let thirty = WidgetHistoryProjection.heatMap(
        providers: [provider],
        range: .days30,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(seven.count == 7)
    #expect(seven.first?.dayStartEpoch == end - 6 * 86_400)
    #expect(seven.last?.dayStartEpoch == end)
    #expect(thirty.count == 30)
    #expect(thirty.first?.dayStartEpoch == end - 29 * 86_400)
}

@Test func singleProviderScopeUsesOnlyTheSelectedProvider() {
    let end = 20 * 86_400
    let cells = WidgetHistoryProjection.heatMap(
        providers: [
            historyProvider(id: "codex", values: [(end, 31)]),
            historyProvider(id: "claude", values: [(end, 1)]),
        ],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "claude",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(cells.last?.value == 1)
    #expect(cells.last?.band == .low)
}

@Test func combinedHeatMapAveragesAvailableProvidersWithoutRounding() {
    let end = 30 * 86_400
    let cells = WidgetHistoryProjection.heatMap(
        providers: [
            historyProvider(id: "codex", values: [(end - 86_400, 5), (end, 5)]),
            historyProvider(id: "claude", values: [(end - 86_400, 6)]),
        ],
        range: .days7,
        scope: .combined,
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(cells[cells.count - 2].value == 5.5)
    #expect(cells[cells.count - 2].band == .moderate)
    #expect(cells.last?.value == 5)
    #expect(cells.last?.band == .low)
    #expect(cells.first?.hasData == false)
}

@Test func heatMapUsesTheProvidersSelectedOuterWindowInsteadOfSourceHistoryOrder() {
    let end = 30 * 86_400
    let provider = multiWindowHistoryProvider(
        id: "codex",
        windows: [("session", "Session"), ("weekly", "Weekly")],
        values: [
            ("session", end, 3),
            ("weekly", end, 27),
        ]
    )

    let cells = WidgetHistoryProjection.heatMap(
        providers: [provider],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(cells.last?.value == 27)
}

@Test func combinedHeatMapResolvesEachProvidersOwnOuterWindowIndependently() {
    let end = 30 * 86_400
    let codex = multiWindowHistoryProvider(
        id: "codex",
        windows: [("session", "Session"), ("weekly", "Weekly")],
        values: [("session", end, 2), ("weekly", end, 20)]
    )
    let claude = multiWindowHistoryProvider(
        id: "claude",
        windows: [("daily", "Daily"), ("billing", "Billing")],
        values: [("daily", end, 4), ("billing", end, 40)]
    )

    let cells = WidgetHistoryProjection.heatMap(
        providers: [codex, claude],
        range: .days7,
        scope: .combined,
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(cells.last?.value == 30)
}

@Test func heatMapUsesLocalMidnightsAcrossSpringDSTAndPreservesTheGap() {
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let march29 = 1_774_738_800
    let march30 = 1_774_821_600
    let march31 = 1_774_908_000
    let provider = historyProvider(
        id: "codex",
        values: [(march29, 5), (march31, 16)]
    )

    let cells = WidgetHistoryProjection.heatMap(
        providers: [provider],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: march31,
        calendar: berlin
    )

    #expect(cells.suffix(3).map(\.dayStartEpoch) == [march29, march30, march31])
    #expect(cells[cells.count - 2].dayStartEpoch - cells[cells.count - 3].dayStartEpoch == 82_800)
    #expect(cells.suffix(3).map(\.value) == [5, nil, 16])
}

@Test func trendUsesLatestPercentagePreservesGapsAndRejectsInvalidValues() throws {
    let end = 50 * 86_400
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: end,
        windows: [WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 25, resetAtEpoch: nil)],
        history: [
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "weekly",
                dayStartEpoch: end - 2 * 86_400,
                consumedPercentPoints: 31,
                latestUsedPercent: 42,
                resetAtEpoch: nil
            ),
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "weekly",
                dayStartEpoch: end,
                consumedPercentPoints: 2,
                latestUsedPercent: 101,
                resetAtEpoch: nil
            ),
        ]
    )

    let points = try #require(WidgetHistoryProjection.trend(
        provider: provider,
        range: .days7,
        windowKind: "weekly",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    ))

    #expect(points.count == 7)
    #expect(points.suffix(3).map(\.latestUsedPercent) == [42, nil, nil])
    #expect(points.last?.dayStartEpoch == end)
}

@Test func currentCycleTrendUsesOnlyTheObservedCycleSuffix() throws {
    let end = 60 * 86_400
    let cycleStart = end - 2 * 86_400 + 3_600
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: end,
        windows: [WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 25, resetAtEpoch: nil)],
        history: (0..<6).map { index in
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "weekly",
                dayStartEpoch: end - (5 - index) * 86_400,
                consumedPercentPoints: index,
                latestUsedPercent: 10 + index,
                resetAtEpoch: nil,
                cycleStartEpoch: index >= 3 ? cycleStart : 1_000
            )
        }
    )

    let points = try #require(WidgetHistoryProjection.trend(
        provider: provider,
        range: .currentCycle,
        windowKind: "weekly",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    ))

    #expect(points.count == 3)
    #expect(points.map(\.dayStartEpoch) == [end - 2 * 86_400, end - 86_400, end])
    #expect(points.map(\.latestUsedPercent) == [13, 14, 15])
}

@Test func currentCycleTrendIsUnavailableWithoutAnObservedBoundary() {
    let end = 60 * 86_400
    let provider = historyProvider(id: "codex", values: [(end, 10)])

    let points = WidgetHistoryProjection.trend(
        provider: provider,
        range: .currentCycle,
        windowKind: "weekly",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    )

    #expect(points == nil)
}

@Test func currentCycleTrendDoesNotInventLeadingGapsBeforeAvailableRows() throws {
    let end = 60 * 86_400
    let oldBoundary = end - 25 * 86_400
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: end,
        windows: [WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 25, resetAtEpoch: nil)],
        history: (0..<3).map { index in
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "weekly",
                dayStartEpoch: end - (2 - index) * 86_400,
                consumedPercentPoints: index,
                latestUsedPercent: 20 + index,
                resetAtEpoch: nil,
                cycleStartEpoch: oldBoundary
            )
        }
    )

    let points = try #require(WidgetHistoryProjection.trend(
        provider: provider,
        range: .currentCycle,
        windowKind: "weekly",
        endingAtDayEpoch: end,
        calendar: utcCalendar
    ))

    #expect(points.count == 3)
    #expect(points.allSatisfy { $0.latestUsedPercent != nil })
}

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

@Test func currentCycleHasAnExactLabelButNoFixedDayCount() {
    #expect(WidgetHistoryPeriod.currentCycle.fixedDayCount == nil)
    #expect(WidgetHistoryPeriod.currentCycle.displayLabel == "Current cycle")
}

private func historyProvider(
    id: String,
    values: [(epoch: Int, value: Int)]
) -> WidgetProviderSnapshot {
    WidgetProviderSnapshot(
        id: id,
        name: id.capitalized,
        status: "ready",
        updatedAtEpoch: values.map(\.epoch).max(),
        windows: [WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 25, resetAtEpoch: nil)],
        history: values.map { value in
            WidgetHistoryDay(
                providerId: id,
                windowKind: "weekly",
                dayStartEpoch: value.epoch,
                consumedPercentPoints: value.value,
                latestUsedPercent: nil,
                resetAtEpoch: nil
            )
        }
    )
}

private func multiWindowHistoryProvider(
    id: String,
    windows: [(kind: String, label: String)],
    values: [(kind: String, epoch: Int, value: Int)]
) -> WidgetProviderSnapshot {
    WidgetProviderSnapshot(
        id: id,
        name: id.capitalized,
        status: "ready",
        updatedAtEpoch: values.map(\.epoch).max(),
        windows: windows.map {
            WidgetWindowSnapshot(
                kind: $0.kind,
                label: $0.label,
                usedPercent: 25,
                resetAtEpoch: nil
            )
        },
        history: values.map {
            WidgetHistoryDay(
                providerId: id,
                windowKind: $0.kind,
                dayStartEpoch: $0.epoch,
                consumedPercentPoints: $0.value,
                latestUsedPercent: nil,
                resetAtEpoch: nil
            )
        }
    )
}
