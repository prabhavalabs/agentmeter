import Testing
@testable import AgentMeterWidgetCore

@Test func timelineOrdersDeduplicatesResetStaleAndCeilingCheckpoints() {
    let now = 10_000
    let snapshot = timelineSnapshot(
        generatedAtEpoch: 9_500,
        pollIntervalSeconds: 300,
        resetEpochs: [9_999, 10_400, 10_400, 100_000]
    )

    let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, nowEpoch: now)

    #expect(plan.currentEpoch == now)
    #expect(plan.checkpoints == [10_400, now + 86_400])
    #expect(plan.reloadAfterEpoch <= now + 86_400)
}

@Test func timelineUsesOnlyTheEarliestFutureResetInsideTwentyFourHours() {
    let now = 10_000
    let snapshot = timelineSnapshot(
        generatedAtEpoch: 10_000,
        pollIntervalSeconds: 10_000,
        resetEpochs: [10_700, 10_500, now + 86_401]
    )

    let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, nowEpoch: now)

    #expect(plan.checkpoints == [10_500, 30_000, now + 86_400])
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

    #expect(WidgetTimelinePlanner.plan(snapshot: staleSnapshot, nowEpoch: now).checkpoints == [now + 86_400])
    #expect(WidgetTimelinePlanner.plan(snapshot: futureSnapshot, nowEpoch: now).checkpoints == [10_400, now + 86_400])
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
