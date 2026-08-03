import AgentMeterCore
import AgentMeterIPC
import AgentMeterUI
import Foundation
import Testing

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
        hiddenProviderIds: ["gemini"],
        providerOrder: ["codex", "claude", "gemini", "cursor"]
    )
    let bridge = ConfirmingSettingsBridge(initial: initial, confirmed: confirmed)
    let model = AppModel(bridge: bridge, preferences: makePreferences())
    await model.start()
    var patch = DeviceSettingsPatch(baseRevision: 3)
    patch.alwaysOn = true

    await model.patchSettings(patch)

    #expect(model.settingsSyncState == .synced)
    #expect(model.pendingSettingsPatch == nil)
    #expect(model.state.revision == 7)
    #expect(model.state.connection == initial.connection)
    #expect(model.state.settings == confirmed)
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
private func makePreferences() -> AppPreferences {
    let name = "AgentMeterModelTests.\(UUID().uuidString)"
    return AppPreferences(defaults: UserDefaults(suiteName: name)!)
}

private func makeState(
    revision: UInt64,
    phase: ConnectionPhase,
    peripherals: [PeripheralSummary] = [],
    managementAvailable: Bool? = true,
    includesSettings: Bool = true
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
                hiddenProviderIds: ["gemini"],
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
