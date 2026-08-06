import AgentMeterCore
import AgentMeterIPC
import AgentMeterUI
import AgentMeterWidgetCore
import Foundation
import Testing

@MainActor
@Test func providerNavigationRequestsDetailFromOverview() {
    let model = AppModel(
        bridge: FakeBridgeAPI(state: makeState(revision: 1, phase: .connected)),
        preferences: makePreferences()
    )
    model.selectedSection = .agents

    model.navigate(to: .provider("codex"))

    #expect(model.selectedSection == .overview)
    #expect(model.requestedProviderDetailID == "codex")
}

@MainActor
@Test func overviewNavigationKeepsPendingProviderDetailRequest() {
    let model = AppModel(
        bridge: FakeBridgeAPI(state: makeState(revision: 1, phase: .connected)),
        preferences: makePreferences()
    )
    model.navigate(to: .provider("codex"))
    model.selectedSection = .agents

    model.navigate(to: .overview)

    #expect(model.selectedSection == .overview)
    #expect(model.requestedProviderDetailID == "codex")
}

@MainActor
@Test func startLoadsStateThenAppliesOnlyNewerEvents() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 4, phase: .connected))
    let model = AppModel(bridge: bridge, preferences: makePreferences())

    await model.start()
    #expect(model.state.revision == 4)
    #expect(model.bridgeReachable)

    await bridge.emitState(makeState(revision: 3, phase: .retrying))
    await allowEventsToDrain()
    #expect(model.state.revision == 4)

    await bridge.emitState(makeState(revision: 5, phase: .degraded))
    await allowEventsToDrain()
    #expect(model.state.revision == 5)
    #expect(model.state.connection.phase == .degraded)

    await model.stop()
}

@MainActor
@Test func scanPublishesDiscoveredDevices() async {
    let peripheral = PeripheralSummary(
        identifier: "device-1",
        name: "AgentMeter-A1B2",
        rssi: -42,
        lastSeenEpoch: 1_785_607_200
    )
    let bridge = FakeBridgeAPI(
        state: makeState(revision: 2, phase: .stopped, peripherals: [peripheral])
    )
    let model = AppModel(bridge: bridge, preferences: makePreferences())

    await model.start()
    await model.scan()

    #expect(model.discoveredDevices == [peripheral])
    #expect(model.activeOperations.isEmpty)
    await model.stop()
}

@MainActor
@Test func settingsPatchAppliesOnlyTheConfirmedSettingsResult() async throws {
    let initial = makeState(revision: 7, phase: .connected)
    let confirmed = DeviceSettings(
        revision: 4,
        alwaysOn: true,
        fullView: false,
        rotationSeconds: 6,
        brightnessPercent: 80,
        dimAfterSeconds: 60,
        screenOffAfterSeconds: 300,
        alertThresholds: [70, 90],
        soundEnabled: false,
        hiddenProviderIds: ["codex"],
        providerOrder: ["codex", "claude", "gemini", "cursor"]
    )
    let bridge = ConfirmingSettingsBridge(initial: initial, confirmed: confirmed)
    let coordinator = RecordingSnapshotCoordinator()
    let model = AppModel(
        bridge: bridge,
        preferences: makePreferences(),
        widgetSnapshotCoordinator: coordinator
    )
    await model.start()
    var patch = DeviceSettingsPatch(baseRevision: 3)
    patch.alwaysOn = true

    await model.patchSettings(patch)

    #expect(model.settingsSyncState == .synced)
    #expect(model.pendingSettingsPatch == nil)
    #expect(model.state.revision == 7)
    #expect(model.state.connection == initial.connection)
    #expect(model.state.settings == confirmed)
    #expect(await coordinator.invalidations() == ["visibilityChanged"])
    await model.stop()
}

@MainActor
@Test func settingsEventsCanRevokeWidgetVisibilityWhileAnOlderRefreshIsInFlight() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 1, phase: .connected))
    let coordinator = RecordingSnapshotCoordinator()
    let model = AppModel(
        bridge: bridge,
        preferences: makePreferences(),
        widgetSnapshotCoordinator: coordinator
    )
    await model.start()
    let gate = ModelRefreshGate()
    await coordinator.blockNextRefresh(on: gate)

    await bridge.emitState(
        makeState(revision: 2, phase: .connected),
        eventType: "providers.changed"
    )
    await gate.waitUntilEntered()
    await bridge.emitState(
        makeState(
            revision: 3,
            phase: .connected,
            hiddenProviderIds: ["codex"]
        ),
        eventType: "settings.changed"
    )
    for _ in 0..<100 where await coordinator.invalidations().isEmpty {
        await Task.yield()
    }

    #expect(await coordinator.invalidations() == ["visibilityChanged"])
    await gate.open()
    await model.stop()
}

@MainActor
@Test func bufferedProviderEventCannotCancelAPendingVisibilityRevocation() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 1, phase: .connected))
    let coordinator = RecordingSnapshotCoordinator()
    let model = AppModel(
        bridge: bridge,
        preferences: makePreferences(),
        widgetSnapshotCoordinator: coordinator
    )
    await model.start()
    let gate = ModelRefreshGate()
    await coordinator.blockNextRefresh(on: gate)
    await bridge.emitState(
        makeState(revision: 2, phase: .connected),
        eventType: "providers.changed"
    )
    await gate.waitUntilEntered()
    let invalidationGate = ModelRefreshGate()
    await coordinator.blockNextInvalidation(on: invalidationGate)

    await bridge.emitState(
        makeState(
            revision: 3,
            phase: .connected,
            hiddenProviderIds: ["codex"]
        ),
        eventType: "settings.changed"
    )
    await invalidationGate.waitUntilEntered()
    await bridge.emitState(
        makeState(
            revision: 4,
            phase: .connected,
            hiddenProviderIds: ["codex"]
        ),
        eventType: "providers.changed"
    )
    for _ in 0..<100 where model.state.revision < 4 {
        await Task.yield()
    }
    await invalidationGate.open()
    for _ in 0..<100 where model.state.revision < 4 {
        await Task.yield()
    }
    #expect(model.state.revision == 4)
    for _ in 0..<100 where await coordinator.invalidations().isEmpty {
        await Task.yield()
    }

    #expect(await coordinator.invalidations() == ["visibilityChanged"])
    await gate.open()
    await model.stop()
}

@MainActor
@Test func clearingHistoryInvalidatesWidgetHistoryWhileARefreshIsInFlight() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 1, phase: .connected))
    let coordinator = RecordingSnapshotCoordinator()
    let model = AppModel(
        bridge: bridge,
        preferences: makePreferences(),
        widgetSnapshotCoordinator: coordinator
    )
    await model.start()
    let gate = ModelRefreshGate()
    await coordinator.blockNextRefresh(on: gate)
    await bridge.emitState(
        makeState(revision: 2, phase: .connected),
        eventType: "providers.changed"
    )
    await gate.waitUntilEntered()

    await model.clearHistory()

    #expect(await coordinator.invalidations() == ["historyCleared"])
    await gate.open()
    await model.stop()
}

@MainActor
@Test func legacyConnectedDeviceNeverReportsSettingsAsSynced() async {
    let bridge = FakeBridgeAPI(
        state: makeState(
            revision: 7,
            phase: .connected,
            managementAvailable: false,
            includesSettings: false
        )
    )
    let model = AppModel(bridge: bridge, preferences: makePreferences())

    await model.start()

    #expect(model.settingsSyncState == .waitingForDevice)
    #expect(model.state.settings == nil)
    await model.stop()
}

@MainActor
@Test func providerAndConnectionEventsUpdateTheSharedState() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 1, phase: .connected))
    let model = AppModel(bridge: bridge, preferences: makePreferences())
    await model.start()

    await bridge.emitState(
        makeState(revision: 2, phase: .degraded),
        eventType: "providers.changed"
    )
    await allowEventsToDrain()

    #expect(model.state.revision == 2)
    #expect(model.state.connection.phase == .degraded)
    await model.stop()
}

@MainActor
@Test func sleepAndWakeAreForwardedToTheBridge() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 1, phase: .connected))
    let model = AppModel(bridge: bridge, preferences: makePreferences())
    await model.start()

    await model.systemWillSleep()
    await model.systemDidWake()

    let commands = await bridge.commandTypes()
    #expect(commands.contains("system.sleep"))
    #expect(commands.contains("system.wake"))
    await model.stop()
}

@MainActor
@Test func changingHistoryRangeReloadsTheSelectedAggregation() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 1, phase: .connected))
    let model = AppModel(bridge: bridge, preferences: makePreferences())
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    await model.start()

    await model.loadHistory(.last7Days, now: now)

    #expect(model.historyRange == .last7Days)
    #expect(await bridge.commandTypes().filter { $0 == "history.query" }.count == 2)
    await model.stop()
}

@MainActor
@Test func appModelPublishesWidgetSnapshotAfterStartupAndExplicitProviderRefresh() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 4, phase: .connected))
    let coordinator = RecordingSnapshotCoordinator()
    let model = AppModel(
        bridge: bridge,
        preferences: makePreferences(),
        widgetSnapshotCoordinator: coordinator
    )

    await model.start()
    #expect(await coordinator.revisions() == [4])

    await model.refreshProviders()
    #expect(await coordinator.revisions() == [4, 4])
    await model.stop()
}

@MainActor
@Test func appModelPublishesOnlyNewerProviderAndStateEvents() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 4, phase: .connected))
    let coordinator = RecordingSnapshotCoordinator()
    let model = AppModel(
        bridge: bridge,
        preferences: makePreferences(),
        widgetSnapshotCoordinator: coordinator
    )
    await model.start()

    await bridge.emitState(
        makeState(revision: 3, phase: .degraded),
        eventType: "providers.changed"
    )
    await bridge.emitState(
        makeState(revision: 5, phase: .degraded),
        eventType: "connection.changed"
    )
    await bridge.emitState(
        makeState(revision: 6, phase: .connected),
        eventType: "providers.changed"
    )
    await bridge.emitState(
        makeState(revision: 6, phase: .connected),
        eventType: "state.changed"
    )
    await bridge.emitState(
        makeState(revision: 7, phase: .connected),
        eventType: "state.changed"
    )
    for _ in 0..<100 where await coordinator.revisions().count < 3 {
        await Task.yield()
    }

    #expect(await coordinator.revisions() == [4, 6, 7])
    await model.stop()
}

@MainActor
@Test func failedPostSaveProviderUpdateImmediatelyRevokesRemovedProviderFromWidget() async throws {
    try await withAppModelTemporaryDirectory { directory in
        let initial = makeProviderCollectionState(
            revision: 1,
            configuredProviderIds: ["codex", "claude"]
        )
        let bridge = ProviderUpdateFailureBridge(state: initial)
        let store = WidgetSnapshotStore(directoryURL: directory)
        let coordinator = WidgetSnapshotCoordinator(
            bridge: bridge,
            store: store,
            reloader: SilentTimelineReloader(),
            calendar: appModelTestCalendar,
            now: { Date(timeIntervalSince1970: 1_774_951_200) }
        )
        let model = AppModel(
            bridge: bridge,
            preferences: makePreferences(),
            widgetSnapshotCoordinator: coordinator
        )
        await model.start()
        var snapshot = try #require(try store.load())
        #expect(model.state.providers.map(\.id) == ["codex", "claude"])
        #expect(snapshot.providers.map(\.id) == ["codex", "claude"])

        await model.updateProviderCollection(
            ids: ["codex"],
            pollIntervalSeconds: 120
        )

        snapshot = try #require(try store.load())
        #expect(model.state.bridge.configuredProviderIds == ["codex"])
        #expect(model.state.providers.map(\.id) == ["codex"])
        #expect(snapshot.providers.map(\.id) == ["codex"])

        await bridge.emitState(
            makeProviderCollectionState(
                revision: 3,
                configuredProviderIds: ["codex", "claude"]
            )
        )
        for _ in 0..<100 where model.state.revision < 3 {
            await Task.yield()
        }
        await coordinator.refresh(state: model.state)
        await model.refreshProviders()

        snapshot = try #require(try store.load())
        #expect(model.state.bridge.configuredProviderIds == ["codex"])
        #expect(model.state.providers.map(\.id) == ["codex"])
        #expect(snapshot.providers.map(\.id) == ["codex"])
        await model.stop()
    }
}

@MainActor
@Test func failedPreSaveProviderUpdateDoesNotRevokeUnconfirmedProvidersFromWidget() async throws {
    try await withAppModelTemporaryDirectory { directory in
        let initial = makeProviderCollectionState(
            revision: 1,
            configuredProviderIds: ["codex", "claude"]
        )
        let bridge = ProviderUpdateFailureBridge(state: initial, failurePoint: .beforeSave)
        let store = WidgetSnapshotStore(directoryURL: directory)
        let coordinator = WidgetSnapshotCoordinator(
            bridge: bridge,
            store: store,
            reloader: SilentTimelineReloader(),
            calendar: appModelTestCalendar,
            now: { Date(timeIntervalSince1970: 1_774_951_200) }
        )
        let model = AppModel(
            bridge: bridge,
            preferences: makePreferences(),
            widgetSnapshotCoordinator: coordinator
        )
        await model.start()

        await model.updateProviderCollection(
            ids: ["codex"],
            pollIntervalSeconds: 120
        )

        let snapshot = try #require(try store.load())
        #expect(model.state.bridge.configuredProviderIds == ["codex", "claude"])
        #expect(model.state.providers.map(\.id) == ["codex", "claude"])
        #expect(snapshot.providers.map(\.id) == ["codex", "claude"])
        await model.stop()
    }
}

@MainActor
@Test func authoritativeProviderProjectionPreservesConfiguredOrderAndHiddenProviderData() async {
    let bridge = FakeBridgeAPI(
        state: makeProviderCollectionState(
            revision: 1,
            configuredProviderIds: ["claude", "codex"],
            hiddenProviderIds: ["claude"]
        )
    )
    let model = AppModel(bridge: bridge, preferences: makePreferences())

    await model.start()

    #expect(model.state.providers.map(\.id) == ["claude", "codex"])
    #expect(model.state.providers.map(\.name) == ["Claude", "Codex"])
    #expect(model.state.settings?.hiddenProviderIds == ["claude"])
    await model.stop()
}

@MainActor
private func makePreferences() -> AppPreferences {
    let name = "AgentMeterModelTests.\(UUID().uuidString)"
    return AppPreferences(defaults: UserDefaults(suiteName: name)!)
}

private func makeState(
    revision: UInt64,
    phase: ConnectionPhase,
    peripherals: [PeripheralSummary] = [],
    managementAvailable: Bool? = true,
    includesSettings: Bool = true,
    hiddenProviderIds: [String] = ["gemini"]
) -> ControlState {
    ControlState(
        revision: revision,
        connection: ConnectionState(
            phase: phase,
            selectedDeviceId: "device-1",
            selectedDeviceName: "AgentMeter-A1B2",
            rssi: -42,
            managementAvailable: managementAvailable
        ),
        peripherals: peripherals,
        settings: includesSettings
            ? DeviceSettings(
                revision: 3,
                alwaysOn: false,
                fullView: false,
                rotationSeconds: 5,
                brightnessPercent: 80,
                dimAfterSeconds: 60,
                screenOffAfterSeconds: 300,
                alertThresholds: [70, 90],
                soundEnabled: false,
                hiddenProviderIds: hiddenProviderIds,
                providerOrder: ["codex", "claude", "gemini", "cursor"]
            )
            : nil,
        bridge: BridgeStatus(version: "0.1.0", running: true)
    )
}

private func allowEventsToDrain() async {
    for _ in 0..<10 {
        await Task.yield()
    }
}

private actor ConfirmingSettingsBridge: BridgeAPI {
    private let initial: ControlState
    private let confirmed: DeviceSettings

    init(initial: ControlState, confirmed: DeviceSettings) {
        self.initial = initial
        self.confirmed = confirmed
    }

    nonisolated func events() -> AsyncThrowingStream<BridgeEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func connect() async throws {}

    func status() async throws -> ControlState {
        initial
    }

    func scan() async throws -> [PeripheralSummary] {
        initial.peripherals
    }

    func perform(_ command: BridgeCommand) async throws -> BridgeResult {
        let payload: JSONValue
        switch command {
        case .patchSettings:
            let settingsData = try JSONEncoder().encode(confirmed)
            let settings = try JSONDecoder().decode(JSONValue.self, from: settingsData)
            payload = .object([
                "syncStatus": .string("synced"),
                "settings": settings,
            ])
        case .queryHistory:
            payload = .object(["usage": .array([])])
        default:
            payload = .object([:])
        }
        return BridgeResult(id: "settings-test", type: "settings.result", payload: payload)
    }

    func close() async {}
}

private enum PostSaveProviderBridgeError: Error {
    case statusUnavailable
    case widgetHistoryUnavailable
}

private enum ProviderUpdateFailurePoint: Equatable, Sendable {
    case afterSave
    case beforeSave
}

private actor ProviderUpdateFailureBridge: BridgeAPI {
    private var state: ControlState
    private var widgetQueriesFail = false
    private var statusUnavailable = false
    private let failurePoint: ProviderUpdateFailurePoint
    private let eventStream: AsyncThrowingStream<BridgeEvent, Error>
    private let eventContinuation: AsyncThrowingStream<BridgeEvent, Error>.Continuation

    init(
        state: ControlState,
        failurePoint: ProviderUpdateFailurePoint = .afterSave
    ) {
        self.state = state
        self.failurePoint = failurePoint
        (eventStream, eventContinuation) = AsyncThrowingStream.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
    }

    nonisolated func events() -> AsyncThrowingStream<BridgeEvent, Error> {
        eventStream
    }

    func connect() async throws {}

    func status() async throws -> ControlState {
        if statusUnavailable {
            throw PostSaveProviderBridgeError.statusUnavailable
        }
        return state
    }

    func scan() async throws -> [PeripheralSummary] {
        state.peripherals
    }

    func perform(_ command: BridgeCommand) async throws -> BridgeResult {
        switch command {
        case let .updateProviders(ids, pollIntervalSeconds):
            if failurePoint == .beforeSave {
                throw BridgeClientError.remote(
                    code: "invalidPayload",
                    message: "Provider settings are invalid",
                    recoverable: false
                )
            }
            let bridge = state.bridge
            state = ControlState(
                revision: state.revision + 1,
                connection: state.connection,
                peripherals: state.peripherals,
                information: state.information,
                telemetry: state.telemetry,
                settings: state.settings,
                providers: state.providers,
                bridge: BridgeStatus(
                    version: bridge.version,
                    running: bridge.running,
                    lastProviderRefreshEpoch: bridge.lastProviderRefreshEpoch,
                    lastDeviceSyncEpoch: bridge.lastDeviceSyncEpoch,
                    lastErrorCode: "providerRefreshFailed",
                    providerHealth: bridge.providerHealth,
                    configuredProviderIds: ids,
                    pollIntervalSeconds: pollIntervalSeconds
                )
            )
            widgetQueriesFail = true
            statusUnavailable = true
            throw BridgeClientError.remote(
                code: "providerRefreshFailed",
                message: "Provider usage could not be refreshed",
                recoverable: true
            )
        case .refreshProviders:
            throw BridgeClientError.remote(
                code: "providerRefreshFailed",
                message: "Provider usage could not be refreshed",
                recoverable: true
            )
        case .queryWidgetHistory:
            if widgetQueriesFail {
                throw PostSaveProviderBridgeError.widgetHistoryUnavailable
            }
            return BridgeResult(
                id: "widget-history",
                type: "history.summary.result",
                payload: try appModelJSONValue(
                    WidgetHistorySummary(historyStartEpoch: nil, days: [])
                )
            )
        case .queryHistory:
            return BridgeResult(
                id: "history",
                type: "history.result",
                payload: try appModelJSONValue(UsageHistoryResult(usage: []))
            )
        case .diagnostics:
            return BridgeResult(
                id: "diagnostics",
                type: "diagnostics.result",
                payload: try appModelJSONValue(
                    BridgeDiagnostics(
                        bridgeVersion: state.bridge.version,
                        ipcSchemaVersion: 1,
                        phase: state.connection.phase.rawValue,
                        managementAvailable: state.connection.managementAvailable,
                        providerHealth: state.bridge.providerHealth,
                        recentEvents: []
                    )
                )
            )
        default:
            return BridgeResult(id: "unused", type: "unused.result", payload: .object([:]))
        }
    }

    func emitState(_ newState: ControlState) {
        state = newState
        let payload = (try? appModelJSONValue(newState)) ?? .object([:])
        eventContinuation.yield(
            BridgeEvent(id: "event-\(newState.revision)", type: "providers.changed", payload: payload)
        )
    }

    func close() async {
        eventContinuation.finish()
    }
}

private actor RecordingSnapshotCoordinator: WidgetSnapshotCoordinating {
    private var recordedRevisions: [UInt64] = []
    private var recordedInvalidations: [String] = []
    private var nextRefreshGate: ModelRefreshGate?
    private var nextInvalidationGate: ModelRefreshGate?

    func refresh(state: ControlState) async {
        recordedRevisions.append(state.revision)
        let gate = nextRefreshGate
        nextRefreshGate = nil
        if let gate { await gate.enter() }
    }

    func invalidate(
        state _: ControlState,
        invalidation: WidgetSnapshotInvalidation
    ) async {
        let gate = nextInvalidationGate
        nextInvalidationGate = nil
        if let gate { await gate.enter() }
        guard Task.isCancelled == false else { return }
        switch invalidation {
        case .visibilityChanged:
            recordedInvalidations.append("visibilityChanged")
        case .historyCleared:
            recordedInvalidations.append("historyCleared")
        }
    }

    func revisions() -> [UInt64] { recordedRevisions }
    func invalidations() -> [String] { recordedInvalidations }

    func blockNextRefresh(on gate: ModelRefreshGate) {
        nextRefreshGate = gate
    }

    func blockNextInvalidation(on gate: ModelRefreshGate) {
        nextInvalidationGate = gate
    }
}

private actor ModelRefreshGate {
    private var entered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        let waitingForEntry = entryWaiters
        entryWaiters.removeAll()
        waitingForEntry.forEach { $0.resume() }
        guard isOpen == false else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard entered == false else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private struct SilentTimelineReloader: WidgetTimelineReloading {
    func reloadWidgetTimelines() async {}
}

private let appModelTestCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func makeProviderCollectionState(
    revision: UInt64,
    configuredProviderIds: [String],
    hiddenProviderIds: [String] = []
) -> ControlState {
    let providers = [
        ProviderSummary(
            id: "codex",
            name: "Codex",
            status: "ok",
            windows: [
                ProviderWindow(
                    kind: "weekly",
                    label: "Weekly",
                    usedPercent: 25,
                    resetAtEpoch: 2_000
                ),
            ],
            updatedAtEpoch: 900
        ),
        ProviderSummary(
            id: "claude",
            name: "Claude",
            status: "ok",
            windows: [
                ProviderWindow(
                    kind: "weekly",
                    label: "Weekly",
                    usedPercent: 35,
                    resetAtEpoch: 2_000
                ),
            ],
            updatedAtEpoch: 900
        ),
    ]
    return ControlState(
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
            providerOrder: ["codex", "claude"]
        ),
        providers: providers,
        bridge: BridgeStatus(
            version: "1",
            running: true,
            lastProviderRefreshEpoch: 1_000,
            configuredProviderIds: configuredProviderIds,
            pollIntervalSeconds: 300
        )
    )
}

@MainActor
private func withAppModelTemporaryDirectory(
    _ body: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppModelWidgetTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}

private func appModelJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
}
