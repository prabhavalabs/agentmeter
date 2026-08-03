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
@Test func settingsRemainConfirmedUntilBridgeRefreshCompletes() async {
    let bridge = FakeBridgeAPI(state: makeState(revision: 7, phase: .connected))
    let model = AppModel(bridge: bridge, preferences: makePreferences())
    await model.start()
    var patch = DeviceSettingsPatch(baseRevision: 3)
    patch.alwaysOn = true

    await model.patchSettings(patch)

    #expect(model.settingsSyncState == .synced)
    #expect(model.pendingSettingsPatch == nil)
    #expect(model.state.settings?.alwaysOn == false)
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
    peripherals: [PeripheralSummary] = []
) -> ControlState {
    ControlState(
        revision: revision,
        connection: ConnectionState(
            phase: phase,
            selectedDeviceId: "device-1",
            selectedDeviceName: "AgentMeter-A1B2",
            rssi: -42,
            managementAvailable: true
        ),
        peripherals: peripherals,
        settings: DeviceSettings(
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
        ),
        bridge: BridgeStatus(version: "0.1.0", running: true)
    )
}

private func allowEventsToDrain() async {
    for _ in 0..<10 {
        await Task.yield()
    }
}
