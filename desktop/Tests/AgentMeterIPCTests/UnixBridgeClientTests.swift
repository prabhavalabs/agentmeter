import AgentMeterCore
import AgentMeterIPC
import Foundation
import Testing

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
