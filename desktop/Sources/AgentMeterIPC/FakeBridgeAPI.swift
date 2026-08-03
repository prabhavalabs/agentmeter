import AgentMeterCore
import Foundation

public actor FakeBridgeAPI: BridgeAPI {
    private var state: ControlState
    private var isConnected = false
    private var receivedCommandTypes: [String] = []
    private let eventStream: AsyncThrowingStream<BridgeEvent, Error>
    private let eventContinuation: AsyncThrowingStream<BridgeEvent, Error>.Continuation

    public init(state: ControlState = .empty) {
        self.state = state
        (eventStream, eventContinuation) = AsyncThrowingStream.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
    }

    public nonisolated func events() -> AsyncThrowingStream<BridgeEvent, Error> {
        eventStream
    }

    public func connect() async throws {
        isConnected = true
    }

    public func status() async throws -> ControlState {
        guard isConnected else { throw BridgeClientError.notConnected }
        return state
    }

    public func scan() async throws -> [PeripheralSummary] {
        state.peripherals
    }

    public func perform(_ command: BridgeCommand) async throws -> BridgeResult {
        receivedCommandTypes.append(command.messageType)
        let type = command.messageType.split(separator: ".").first.map(String.init) ?? "command"
        let payload: JSONValue
        switch command {
        case .queryHistory:
            payload = try UsageHistoryResult(usage: []).jsonValue()
        case .diagnostics:
            payload = try BridgeDiagnostics(
                bridgeVersion: state.bridge.version,
                ipcSchemaVersion: 1,
                phase: state.connection.phase.rawValue,
                managementAvailable: state.connection.managementAvailable,
                providerHealth: state.bridge.providerHealth,
                recentEvents: []
            ).jsonValue()
        default:
            payload = .object([:])
        }
        return BridgeResult(id: UUID().uuidString, type: "\(type).result", payload: payload)
    }

    public func emitState(_ newState: ControlState, eventType: String = "state.changed") {
        state = newState
        let payload = (try? newState.jsonValue()) ?? .object([:])
        eventContinuation.yield(
            BridgeEvent(id: "event-\(newState.revision)", type: eventType, payload: payload)
        )
    }

    public func commandTypes() -> [String] {
        receivedCommandTypes
    }

    public func close() async {
        isConnected = false
        eventContinuation.finish()
    }

    public func drain() async {
        await Task.yield()
    }
}
