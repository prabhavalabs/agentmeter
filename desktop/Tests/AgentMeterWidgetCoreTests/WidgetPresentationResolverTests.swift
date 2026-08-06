import AgentMeterCore
import Testing
@testable import AgentMeterWidgetCore

@Test(arguments: [
    (WidgetFamily.small, 2),
    (.medium, 4),
    (.large, 5),
    (.extraLarge, 8),
])
func dashboardProviderMaximaAndOverflow(family: WidgetFamily, maximum: Int) {
    let snapshot = presentationSnapshot(providerCount: 8)
    let presentation = WidgetPresentationResolver.resolve(
        configuration: dashboardConfiguration(providerIDs: snapshot.providers.map(\.id)),
        snapshot: snapshot,
        family: family,
        nowEpoch: 2_000
    )

    #expect(presentation.providers.count == maximum)
    #expect(presentation.overflowCount == 8 - maximum)
}

@Test func compactFamiliesRemoveModulesInPriorityOrderAndKeepEssentials() {
    let snapshot = presentationSnapshot(providerCount: 5)
    let requested = dashboardConfiguration(providerIDs: snapshot.providers.map(\.id))

    let small = WidgetPresentationResolver.resolve(
        configuration: requested,
        snapshot: snapshot,
        family: .small,
        nowEpoch: 2_000
    )
    let medium = WidgetPresentationResolver.resolve(
        configuration: requested,
        snapshot: snapshot,
        family: .medium,
        nowEpoch: 2_000
    )

    #expect(small.modules == [.usage, .primaryReset])
    #expect(small.providers.count == 2)
    #expect(medium.modules == [.usage, .primaryReset, .status, .freshness])
    #expect(medium.providers.count == 4)
    #expect(small.modules.contains(.usage))
    #expect(small.modules.contains(.primaryReset))
}

@Test func mediumAlwaysRemovesHistoryFromASparseRequest() {
    let snapshot = presentationSnapshot(providerCount: 1)
    let requested = dashboardConfiguration(
        providerIDs: ["provider-0"],
        modules: [.usage, .primaryReset, .history]
    )

    let presentation = WidgetPresentationResolver.resolve(
        configuration: requested,
        snapshot: snapshot,
        family: .medium,
        nowEpoch: 2_000
    )

    #expect(presentation.modules == [.usage, .primaryReset])
    #expect(presentation.history == nil)
}

@Test func focusUsesExplicitWindowsAndExplainsUnavailableHistory() {
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: 1_900,
        windows: (0..<5).map {
            WidgetWindowSnapshot(kind: "window-\($0)", label: "Window \($0)", usedPercent: 10 + $0, resetAtEpoch: 4_000 + $0)
        },
        history: (0..<4).map {
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "window-\($0)",
                dayStartEpoch: 86_400,
                consumedPercentPoints: $0,
                latestUsedPercent: 10 + $0,
                resetAtEpoch: nil
            )
        }
    )
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: 1_900,
        pollIntervalSeconds: 300,
        historyStartEpoch: 86_400,
        providers: [provider]
    )
    let configuration = focusConfiguration(outer: "window-4", inner: "window-2")

    let presentation = WidgetPresentationResolver.resolve(
        configuration: configuration,
        snapshot: snapshot,
        family: .large,
        nowEpoch: 2_000,
        endingAtDayEpoch: 86_400
    )

    #expect(presentation.providers.first?.rings.map(\.windowKind) == ["window-4", "window-2"])
    #expect(presentation.history?.availabilityMessage == "History unavailable for this window")
    #expect(presentation.history?.cells.isEmpty == true)
}

@Test func eligibleFocusWindowWithoutRowsProducesGapsInsteadOfUnavailableHistory() {
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: 1_900,
        windows: (0..<5).map { (index: Int) in
            WidgetWindowSnapshot(
                kind: "window-\(index)",
                label: "Window \(index)",
                usedPercent: index,
                resetAtEpoch: nil
            )
        },
        history: []
    )
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: 1_900,
        pollIntervalSeconds: 300,
        historyStartEpoch: nil,
        providers: [provider]
    )

    let presentation = WidgetPresentationResolver.resolve(
        configuration: focusConfiguration(outer: "window-0", inner: nil),
        snapshot: snapshot,
        family: .large,
        nowEpoch: 2_000,
        endingAtDayEpoch: 86_400
    )

    #expect(presentation.history?.availabilityMessage == nil)
    #expect(presentation.history?.cells.count == 7)
    #expect(presentation.history?.cells.allSatisfy { $0.hasData == false } == true)
}

@Test func ineligibleFocusWindowStaysUnavailableDespiteAStrayHistoryRow() {
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: 1_900,
        windows: (0..<5).map { (index: Int) in
            WidgetWindowSnapshot(
                kind: "window-\(index)",
                label: "Window \(index)",
                usedPercent: index,
                resetAtEpoch: nil
            )
        },
        history: [
            WidgetHistoryDay(
                providerId: "codex",
                windowKind: "window-4",
                dayStartEpoch: 86_400,
                consumedPercentPoints: 31,
                latestUsedPercent: 31,
                resetAtEpoch: nil
            ),
        ]
    )
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: 1_900,
        pollIntervalSeconds: 300,
        historyStartEpoch: 86_400,
        providers: [provider]
    )

    let presentation = WidgetPresentationResolver.resolve(
        configuration: focusConfiguration(outer: "window-4", inner: nil),
        snapshot: snapshot,
        family: .large,
        nowEpoch: 2_000,
        endingAtDayEpoch: 86_400
    )

    #expect(presentation.history?.availabilityMessage == "History unavailable for this window")
    #expect(presentation.history?.cells.isEmpty == true)
}

@Test func staleAndPassedResetStatesAreResolvedWithoutChangingUsage() {
    let provider = WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "ready",
        updatedAtEpoch: 1_000,
        windows: [WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: 73, resetAtEpoch: 1_999)],
        history: []
    )
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: 1_000,
        pollIntervalSeconds: 300,
        historyStartEpoch: nil,
        providers: [provider]
    )

    let presentation = WidgetPresentationResolver.resolve(
        configuration: focusConfiguration(outer: "weekly", inner: nil),
        snapshot: snapshot,
        family: .large,
        nowEpoch: 2_000
    )

    #expect(presentation.freshness == .stale)
    #expect(presentation.providers.first?.rings.first?.usedPercent == 73)
    #expect(presentation.providers.first?.rings.first?.resetState == .pending)
    #expect(presentation.providers.first?.rings.first?.resetText == "Refresh pending")
}

@Test func invalidPollIntervalsUseTheFifteenMinuteStaleThreshold() {
    let snapshot = WidgetSnapshot(
        generatedAtEpoch: 1_000,
        pollIntervalSeconds: 0,
        historyStartEpoch: nil,
        providers: []
    )
    let before = WidgetPresentationResolver.resolve(
        configuration: dashboardConfiguration(providerIDs: []),
        snapshot: snapshot,
        family: .large,
        nowEpoch: 1_899
    )
    let atThreshold = WidgetPresentationResolver.resolve(
        configuration: dashboardConfiguration(providerIDs: []),
        snapshot: snapshot,
        family: .large,
        nowEpoch: 1_900
    )

    #expect(before.freshness == .fresh)
    #expect(atThreshold.freshness == .stale)
}

private func dashboardConfiguration(
    providerIDs: [String],
    modules: Set<WidgetModule> = [.usage, .primaryReset, .history, .status, .freshness]
) -> WidgetRenderConfiguration {
    WidgetRenderConfiguration(
        kind: .dashboard,
        providerIDs: providerIDs,
        focusProviderID: nil,
        outerWindowKind: nil,
        innerWindowKind: nil,
        percentageMode: .used,
        modules: modules,
        historyStyle: .heatMap,
        historyPeriod: .days30,
        heatMapScope: .combined,
        layout: .automatic,
        density: .comfortable,
        theme: .system,
        tapDestination: .dashboard
    )
}

private func focusConfiguration(outer: String?, inner: String?) -> WidgetRenderConfiguration {
    WidgetRenderConfiguration(
        kind: .focus,
        providerIDs: ["codex"],
        focusProviderID: "codex",
        outerWindowKind: outer,
        innerWindowKind: inner,
        percentageMode: .used,
        modules: [.usage, .primaryReset, .history, .status, .freshness],
        historyStyle: .heatMap,
        historyPeriod: .days7,
        heatMapScope: .singleProvider,
        layout: .automatic,
        density: .comfortable,
        theme: .system,
        tapDestination: .dashboard
    )
}

private func presentationSnapshot(providerCount: Int) -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAtEpoch: 1_900,
        pollIntervalSeconds: 300,
        historyStartEpoch: nil,
        providers: (0..<providerCount).map { index in
            WidgetProviderSnapshot(
                id: "provider-\(index)",
                name: "Provider \(index)",
                status: "ready",
                updatedAtEpoch: 1_900,
                windows: [WidgetWindowSnapshot(kind: "weekly", label: "Weekly", usedPercent: index, resetAtEpoch: 4_000)],
                history: []
            )
        }
    )
}
