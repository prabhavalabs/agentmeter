import AgentMeterCore
import Testing
@testable import AgentMeterIPC

@Test func fakeBridgeRequiresConnectionAndReturnsState() async throws {
    let state = ControlState.empty
    let bridge = FakeBridgeAPI(state: state)

    await #expect(throws: BridgeClientError.notConnected) {
        try await bridge.status()
    }
    try await bridge.connect()
    #expect(try await bridge.status() == state)
}

@Test func fakeBridgeEmitsCompleteStateEvents() async throws {
    let bridge = FakeBridgeAPI()
    let stream = bridge.events()
    let pending = Task { try await stream.first { _ in true } }
    let next = ControlState(
        revision: 4,
        connection: ConnectionState(phase: .connected),
        bridge: BridgeStatus(version: "0.1.0", running: true)
    )

    await bridge.emitState(next)
    let event = try #require(await pending.value)

    #expect(event.type == "state.changed")
    #expect(try event.decodePayload(ControlState.self) == next)
    await bridge.close()
}
