import AgentMeterCore
@testable import AgentMeterIPC
import Foundation
import Network
import Testing

@Test func waitingUnixConnectionFailsSoTheAppCanRetry() {
    let state = NWConnection.State.waiting(.posix(.ECONNREFUSED))
    guard case let .connectionFailed(message) = UnixBridgeClient.connectionError(for: state) else {
        Issue.record("A waiting connection did not produce a retryable error")
        return
    }
    #expect(message.isEmpty == false)
}

@Test(
    "Unix client exchanges status and commands with the Python bridge",
    .enabled(if: ProcessInfo.processInfo.environment["AGENTMETER_IPC_TEST_PATH"] != nil)
)
func unixClientIntegration() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["AGENTMETER_IPC_TEST_PATH"])
    let client = UnixBridgeClient(path: path)

    try await client.connect()
    let initial = try await client.status()
    #expect(initial.connection.phase == .connected)
    #expect(initial.providers.isEmpty == false)

    let peripherals = try await client.scan()
    #expect(peripherals.first?.name == "AgentMeter-A1B2")

    _ = try await client.perform(.disconnectDevice)
    let stopped = try await client.status()
    #expect(stopped.connection.phase == .stopped)

    await client.close()
}

@Test(
    "Unix client reads a live bridge without changing device state",
    .enabled(if: ProcessInfo.processInfo.environment["AGENTMETER_IPC_STATUS_TEST_PATH"] != nil)
)
func unixClientStatusIntegration() async throws {
    let path = try #require(
        ProcessInfo.processInfo.environment["AGENTMETER_IPC_STATUS_TEST_PATH"]
    )
    let client = UnixBridgeClient(path: path)

    try await client.connect()
    let state = try await client.status()
    #expect(state.bridge.running)
    #expect(state.bridge.configuredProviderIds.isEmpty == false)

    await client.close()
}
