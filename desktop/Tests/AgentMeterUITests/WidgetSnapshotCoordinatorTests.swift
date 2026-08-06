import AgentMeterCore
import AgentMeterIPC
import AgentMeterUI
import AgentMeterWidgetCore
import Foundation
import Testing

@Test func widgetCoordinatorQueriesFirstEightVisibleProvidersInConfiguredOrder() async throws {
    try await withTemporaryDirectory { directory in
        let providers = (0..<10).map { makeProvider(id: "provider-\($0)", usedPercent: $0) }
        let configuredOrder = (0..<10).reversed().map { "provider-\($0)" }
        let bridge = RecordingWidgetBridge()
        let reloader = RecordingTimelineReloader()
        let store = WidgetSnapshotStore(directoryURL: directory)
        let coordinator = WidgetSnapshotCoordinator(
            bridge: bridge,
            store: store,
            reloader: reloader,
            calendar: berlinCalendar,
            now: { Date(timeIntervalSince1970: 1_774_951_200) }
        )
        let state = makeCoordinatorState(
            revision: 1,
            providers: providers,
            providerOrder: configuredOrder,
            hiddenProviderIds: ["provider-8"]
        )

        await coordinator.refresh(state: state)

        let queries = await bridge.recordedQueries()
        #expect(queries.map(\.providerId) == [
            "provider-9", "provider-7", "provider-6", "provider-5",
            "provider-4", "provider-3", "provider-2", "provider-1",
        ])
        #expect(queries.allSatisfy { $0.sinceEpoch == 1_772_406_000 })
        #expect(queries.allSatisfy { $0.timeZoneIdentifier == "Europe/Berlin" })
        let snapshot = try store.load()
        #expect(snapshot?.providers.map(\.id) == queries.map(\.providerId))
        #expect(await reloader.reloadCount() == 1)
    }
}

@Test func widgetCoordinatorReloadsOnlyWhenCanonicalSnapshotBytesChange() async throws {
    try await withTemporaryDirectory { directory in
        let bridge = RecordingWidgetBridge()
        let reloader = RecordingTimelineReloader()
        let store = WidgetSnapshotStore(directoryURL: directory)
        let coordinator = WidgetSnapshotCoordinator(
            bridge: bridge,
            store: store,
            reloader: reloader,
            calendar: berlinCalendar,
            now: { Date(timeIntervalSince1970: 1_774_951_200) }
        )
        let initial = makeCoordinatorState(
            revision: 1,
            providers: [makeProvider(id: "codex", usedPercent: 25)],
            providerOrder: ["codex"]
        )

        await coordinator.refresh(state: initial)
        await coordinator.refresh(state: initial)
        #expect(await reloader.reloadCount() == 1)

        let changed = makeCoordinatorState(
            revision: 2,
            providers: [makeProvider(id: "codex", usedPercent: 26)],
            providerOrder: ["codex"]
        )
        await coordinator.refresh(state: changed)

        #expect(await reloader.reloadCount() == 2)
        let snapshot = try store.load()
        #expect(snapshot?.providers[0].windows[0].usedPercent == 26)
    }
}

@Test func widgetCoordinatorRetainsOnlyFailedProvidersCachedHistory() async throws {
    try await withTemporaryDirectory { directory in
        let bridge = RecordingWidgetBridge(summaries: [
            "codex": makeSummary(providerId: "codex", consumed: 5),
            "claude": makeSummary(providerId: "claude", consumed: 7),
        ])
        let store = WidgetSnapshotStore(directoryURL: directory)
        let coordinator = WidgetSnapshotCoordinator(
            bridge: bridge,
            store: store,
            reloader: RecordingTimelineReloader(),
            calendar: berlinCalendar,
            now: { Date(timeIntervalSince1970: 1_774_951_200) }
        )
        let firstState = makeCoordinatorState(
            revision: 1,
            providers: [
                makeProvider(id: "codex", usedPercent: 25),
                makeProvider(id: "claude", usedPercent: 35),
            ],
            providerOrder: ["codex", "claude"]
        )
        await coordinator.refresh(state: firstState)

        await bridge.setSummary(makeSummary(providerId: "claude", consumed: 11), for: "claude")
        await bridge.setFailure(true, for: "codex")
        let secondState = makeCoordinatorState(
            revision: 2,
            providers: [
                makeProvider(id: "codex", usedPercent: 26),
                makeProvider(id: "claude", usedPercent: 36),
            ],
            providerOrder: ["codex", "claude"]
        )

        await coordinator.refresh(state: secondState)

        let loadedSnapshot = try store.load()
        let snapshot = try #require(loadedSnapshot)
        #expect(snapshot.providers[0].history.map(\.consumedPercentPoints) == [5])
        #expect(snapshot.providers[1].history.map(\.consumedPercentPoints) == [11])
        #expect(await bridge.recordedQueries().count == 4)
    }
}

@Test func widgetCoordinatorDoesNotReloadAfterPublicationFailure() async throws {
    try await withTemporaryDirectory { directory in
        let store = WidgetSnapshotStore(directoryURL: directory)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        let reloader = RecordingTimelineReloader()
        let coordinator = WidgetSnapshotCoordinator(
            bridge: RecordingWidgetBridge(),
            store: store,
            reloader: reloader,
            calendar: berlinCalendar,
            now: { Date(timeIntervalSince1970: 1_774_951_200) }
        )

        await coordinator.refresh(
            state: makeCoordinatorState(
                revision: 1,
                providers: [makeProvider(id: "codex", usedPercent: 25)],
                providerOrder: ["codex"]
            )
        )

        #expect(await reloader.reloadCount() == 0)
    }
}

private let berlinCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private struct WidgetQuery: Equatable, Sendable {
    let sinceEpoch: Int
    let providerId: String
    let timeZoneIdentifier: String
}

private enum WidgetBridgeTestError: Error {
    case summaryUnavailable
}

private actor RecordingWidgetBridge: BridgeAPI {
    private var summaries: [String: WidgetHistorySummary]
    private var failures: Set<String> = []
    private var queries: [WidgetQuery] = []

    init(summaries: [String: WidgetHistorySummary] = [:]) {
        self.summaries = summaries
    }

    nonisolated func events() -> AsyncThrowingStream<BridgeEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func connect() async throws {}
    func status() async throws -> ControlState { .empty }
    func scan() async throws -> [PeripheralSummary] { [] }

    func perform(_ command: BridgeCommand) async throws -> BridgeResult {
        guard case let .queryWidgetHistory(sinceEpoch, providerId, timeZoneIdentifier) = command else {
            return BridgeResult(id: "unused", type: "unused.result", payload: .object([:]))
        }
        queries.append(
            WidgetQuery(
                sinceEpoch: sinceEpoch,
                providerId: providerId,
                timeZoneIdentifier: timeZoneIdentifier
            )
        )
        if failures.contains(providerId) { throw WidgetBridgeTestError.summaryUnavailable }
        let summary = summaries[providerId] ?? WidgetHistorySummary(historyStartEpoch: nil, days: [])
        return BridgeResult(
            id: "history-test",
            type: "history.summary.result",
            payload: try JSONDecoder().decode(
                JSONValue.self,
                from: JSONEncoder().encode(summary)
            )
        )
    }

    func close() async {}

    func setSummary(_ summary: WidgetHistorySummary, for providerId: String) {
        summaries[providerId] = summary
    }

    func setFailure(_ shouldFail: Bool, for providerId: String) {
        if shouldFail {
            failures.insert(providerId)
        } else {
            failures.remove(providerId)
        }
    }

    func recordedQueries() -> [WidgetQuery] { queries }
}

private actor RecordingTimelineReloader: WidgetTimelineReloading {
    private var count = 0

    func reloadWidgetTimelines() async {
        count += 1
    }

    func reloadCount() -> Int { count }
}

private func makeCoordinatorState(
    revision: UInt64,
    providers: [ProviderSummary],
    providerOrder: [String],
    hiddenProviderIds: [String] = []
) -> ControlState {
    ControlState(
        revision: revision,
        connection: ConnectionState(phase: .connected),
        settings: DeviceSettings(
            revision: revision,
            alwaysOn: false,
            fullView: false,
            rotationSeconds: 5,
            brightnessPercent: 80,
            dimAfterSeconds: 60,
            screenOffAfterSeconds: 300,
            alertThresholds: [70, 90],
            soundEnabled: false,
            hiddenProviderIds: hiddenProviderIds,
            providerOrder: providerOrder
        ),
        providers: providers,
        bridge: BridgeStatus(
            version: "1",
            running: true,
            lastProviderRefreshEpoch: Int(revision) * 1_000,
            configuredProviderIds: providerOrder,
            pollIntervalSeconds: 300
        )
    )
}

private func makeProvider(id: String, usedPercent: Int) -> ProviderSummary {
    ProviderSummary(
        id: id,
        name: id.capitalized,
        status: "ready",
        windows: [
            ProviderWindow(
                kind: "weekly",
                label: "Weekly",
                usedPercent: usedPercent,
                resetAtEpoch: 2_000
            ),
        ],
        updatedAtEpoch: 900
    )
}

private func makeSummary(providerId: String, consumed: Int) -> WidgetHistorySummary {
    WidgetHistorySummary(
        historyStartEpoch: 1_772_406_000,
        days: [
            WidgetHistoryDay(
                providerId: providerId,
                windowKind: "weekly",
                dayStartEpoch: 1_772_406_000,
                consumedPercentPoints: consumed,
                latestUsedPercent: consumed,
                resetAtEpoch: 2_000
            ),
        ]
    )
}

private func withTemporaryDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WidgetSnapshotCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}
