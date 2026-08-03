import AgentMeterCore
import Foundation

public actor FakeBridgeAPI: BridgeAPI {
    private var state: ControlState
    private var isConnected = false
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
        let type = command.messageType.split(separator: ".").first.map(String.init) ?? "command"
        return BridgeResult(id: UUID().uuidString, type: "\(type).result", payload: .object([:]))
    }

    public func emitState(_ newState: ControlState) {
        state = newState
        let payload = (try? newState.jsonValue()) ?? .object([:])
        eventContinuation.yield(
            BridgeEvent(id: "event-\(newState.revision)", type: "state.changed", payload: payload)
        )
    }

    public func close() async {
        isConnected = false
        eventContinuation.finish()
    }

    public func drain() async {
        await Task.yield()
    }
}
