import Testing
@testable import AgentMeterWidgetCore

@Test func timelineOrdersDeduplicatesResetStaleAndCeilingCheckpoints() {
    let now = 10_000
    let snapshot = timelineSnapshot(
        generatedAtEpoch: 9_500,
        pollIntervalSeconds: 300,
        resetEpochs: [9_999, 10_400, 10_400, 100_000]
    )

    let plan = WidgetTimelinePlanner.plan(
        snapshot: snapshot,
        configuration: timelineConfiguration(),
        family: .large,
        nowEpoch: now
    )

    #expect(plan.currentEpoch == now)
    #expect(plan.checkpoints == [10_400, now + 86_400])
    #expect(plan.reloadAfterEpoch <= now + 86_400)
}

@Test func timelineUsesEveryDistinctFutureResetInsideTwentyFourHours() {
    let now = 10_000
    let snapshot = timelineSnapshot(
        generatedAtEpoch: 10_000,
        pollIntervalSeconds: 10_000,
        resetEpochs: [10_700, 10_500, now + 86_401]
    )

    let plan = WidgetTimelinePlanner.plan(
        snapshot: snapshot,
        configuration: timelineConfiguration(),
        family: .large,
        nowEpoch: now
    )

    #expect(plan.checkpoints == [10_500, 10_700, 30_000, now + 86_400])
}

@Test func timelineIncludesOnlyProvidersSelectedAndRenderedByTheConfiguration() {
    let now = 10_000
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: now,
        pollIntervalSeconds: 10_000,
        historyStartEpoch: nil,
        providers: [
            timelineProvider(id: "codex", resetEpochs: [10_300, 10_500]),
            timelineProvider(id: "claude", resetEpochs: [10_700]),
        ]
    )

    let plan = WidgetTimelinePlanner.plan(
        snapshot: snapshot,
        configuration: timelineConfiguration(
            kind: .focus,
            providerIDs: ["claude"],
            focusProviderID: "claude"
        ),
        family: .medium,
        nowEpoch: now
    )

    #expect(plan.checkpoints == [10_700, 30_000, now + 86_400])
}

@Test func timelineOmitsTruncatedAdditionalResetsButKeepsBothVisibleFocusRings() {
    let now = 10_000
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: now,
        pollIntervalSeconds: 10_000,
        historyStartEpoch: nil,
        providers: [
            WidgetProviderSnapshot(
                id: "codex",
                name: "Codex",
                status: "ready",
                updatedAtEpoch: now,
                windows: [
                    WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 30, resetAtEpoch: 10_300),
                    WidgetWindowSnapshot(kind: "session", label: "Session", usedPercent: 10, resetAtEpoch: 10_400),
                    WidgetWindowSnapshot(kind: "daily", label: "Daily", usedPercent: 5, resetAtEpoch: 10_500),
                ],
                history: []
            ),
        ]
    )

    let plan = WidgetTimelinePlanner.plan(
        snapshot: snapshot,
        configuration: timelineConfiguration(
            kind: .focus,
            providerIDs: ["codex"],
            focusProviderID: "codex"
        ),
        family: .small,
        nowEpoch: now
    )

    #expect(plan.checkpoints == [10_300, 10_400, 30_000, now + 86_400])
}

@Test func timelineOmitsPastStaleTransitionAndFallsBackForInvalidPolling() {
    let now = 10_000
    let staleSnapshot = timelineSnapshot(
        generatedAtEpoch: 8_000,
        pollIntervalSeconds: 0,
        resetEpochs: []
    )
    let futureSnapshot = timelineSnapshot(
        generatedAtEpoch: 9_500,
        pollIntervalSeconds: -1,
        resetEpochs: []
    )

    #expect(WidgetTimelinePlanner.plan(
        snapshot: staleSnapshot,
        configuration: timelineConfiguration(),
        family: .large,
        nowEpoch: now
    ).checkpoints == [now + 86_400])
    #expect(WidgetTimelinePlanner.plan(
        snapshot: futureSnapshot,
        configuration: timelineConfiguration(),
        family: .large,
        nowEpoch: now
    ).checkpoints == [10_400, now + 86_400])
}

private func timelineProvider(id: String, resetEpochs: [Int]) -> WidgetProviderSnapshot {
    WidgetProviderSnapshot(
        id: id,
        name: id.capitalized,
        status: "ready",
        updatedAtEpoch: 10_000,
        windows: resetEpochs.enumerated().map { index, epoch in
            WidgetWindowSnapshot(
                kind: "window-\(index)",
                label: "Window \(index)",
                usedPercent: 50,
                resetAtEpoch: epoch
            )
        },
        history: []
    )
}

private func timelineConfiguration(
    kind: WidgetKind = .dashboard,
    providerIDs: [String] = [],
    focusProviderID: String? = nil
) -> WidgetRenderConfiguration {
    WidgetRenderConfiguration(
        kind: kind,
        providerIDs: providerIDs,
        focusProviderID: focusProviderID,
        outerWindowKind: nil,
        innerWindowKind: nil,
        percentageMode: .used,
        modules: [.usage, .primaryReset],
        historyStyle: .none,
        historyPeriod: .days7,
        heatMapScope: .singleProvider,
        layout: .automatic,
        density: .comfortable,
        theme: .system,
        tapDestination: .overview
    )
}

private func timelineSnapshot(
    generatedAtEpoch: Int,
    pollIntervalSeconds: Int,
    resetEpochs: [Int]
) -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAtEpoch: generatedAtEpoch,
        pollIntervalSeconds: pollIntervalSeconds,
        historyStartEpoch: nil,
        providers: [
            WidgetProviderSnapshot(
                id: "codex",
                name: "Codex",
                status: "ready",
                updatedAtEpoch: generatedAtEpoch,
                windows: resetEpochs.enumerated().map { index, epoch in
                    WidgetWindowSnapshot(kind: "window-\(index)", label: "Window \(index)", usedPercent: 50, resetAtEpoch: epoch)
                },
                history: []
            ),
        ]
    )
}
