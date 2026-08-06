import AgentMeterCore
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
        endingAtDayEpoch: end
    )

    #expect(cells.map(\.band) == [.zero, .low, .low, .moderate, .moderate, .high, .veryHigh])
    #expect(cells.allSatisfy { $0.hasData })

    let withGap = WidgetHistoryProjection.heatMap(
        providers: [historyProvider(id: "codex", values: [(end, 0)])],
        range: .days7,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end
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
        endingAtDayEpoch: end
    )
    let thirty = WidgetHistoryProjection.heatMap(
        providers: [provider],
        range: .days30,
        scope: .singleProvider,
        selectedProviderID: "codex",
        endingAtDayEpoch: end
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
        endingAtDayEpoch: end
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
        endingAtDayEpoch: end
    )

    #expect(cells[cells.count - 2].value == 5.5)
    #expect(cells[cells.count - 2].band == .moderate)
    #expect(cells.last?.value == 5)
    #expect(cells.last?.band == .low)
    #expect(cells.first?.hasData == false)
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
