import AgentMeterCore
import Foundation
import Network

public actor UnixBridgeClient: BridgeAPI {
    private let path: String
    private let queue = DispatchQueue(label: "com.prabhavalabs.agentmeter.ipc")
    private var connection: NWConnection?
    private var decoder = JsonLineDecoder()
    private var pending: [String: CheckedContinuation<BridgeResult, any Error>] = [:]
    private var isReady = false
    private let eventStream: AsyncThrowingStream<BridgeEvent, Error>
    private let eventContinuation: AsyncThrowingStream<BridgeEvent, Error>.Continuation

    public init(path: String) {
        self.path = path
        (eventStream, eventContinuation) = AsyncThrowingStream.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
    }

    public nonisolated func events() -> AsyncThrowingStream<BridgeEvent, Error> {
        eventStream
    }

    public func connect() async throws {
        guard !isReady else { return }
        let activeConnection = NWConnection(to: .unix(path: path), using: .tcp)
        connection = activeConnection
        do {
            try await withCheckedThrowingContinuation { continuation in
                let gate = ConnectionGate(continuation)
                activeConnection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.succeed()
                    default:
                        if let error = Self.connectionError(for: state) {
                            gate.fail(error)
                        }
                    }
                }
                activeConnection.start(queue: queue)
            }
        } catch {
            activeConnection.stateUpdateHandler = nil
            activeConnection.cancel()
            connection = nil
            throw error
        }
        isReady = true
        receiveNext()
        _ = try await request(type: "hello", payload: [:])
        _ = try await request(type: "events.subscribe", payload: [:])
    }

    nonisolated static func connectionError(
        for state: NWConnection.State
    ) -> BridgeClientError? {
        switch state {
        case let .failed(error), let .waiting(error):
            .connectionFailed(error.localizedDescription)
        case .cancelled:
            .disconnected
        default:
            nil
        }
    }

    public func status() async throws -> ControlState {
        let result = try await request(type: "status.get", payload: [:])
        return try result.decodePayload(ControlState.self)
    }

    public func scan() async throws -> [PeripheralSummary] {
        let result = try await request(type: "device.scan", payload: [:])
        return try result.decodePayload(PeripheralResult.self).peripherals
    }

    public func perform(_ command: BridgeCommand) async throws -> BridgeResult {
        try await request(type: command.messageType, payload: command.payload())
    }

    public func close() async {
        guard connection != nil || isReady else {
            eventContinuation.finish()
            return
        }
        finish(.disconnected, terminateEvents: true)
    }

    private func request(
        type: String,
        payload: [String: JSONValue]
    ) async throws -> BridgeResult {
        guard isReady, let connection else { throw BridgeClientError.notConnected }
        let id = UUID().uuidString.lowercased()
        let envelope = IpcRequestEnvelope(id: id, type: type, payload: payload)
        var data = try JSONEncoder().encode(envelope)
        data.append(0x0A)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { await self?.failRequest(id: id, error: error) }
            })
        }
    }

    private func receiveNext() {
        guard let connection, isReady else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) {
            [weak self] data, _, complete, error in
            Task { await self?.received(data: data, complete: complete, error: error) }
        }
    }

    private func received(data: Data?, complete: Bool, error: NWError?) {
        if let error {
            finish(.connectionFailed(error.localizedDescription), terminateEvents: false)
            return
        }
        do {
            for frame in try decoder.append(data ?? Data()) {
                try handle(frame)
            }
            if complete {
                try decoder.finish()
                finish(.disconnected, terminateEvents: false)
                return
            }
        } catch let error as BridgeClientError {
            finish(error, terminateEvents: false)
            return
        } catch {
            finish(.invalidFrame, terminateEvents: false)
            return
        }
        receiveNext()
    }

    private func handle(_ frame: Data) throws {
        let envelope = try JSONDecoder().decode(IncomingEnvelope.self, from: frame)
        guard envelope.schemaVersion == 1 else { throw BridgeClientError.invalidFrame }
        if let status = envelope.status {
            guard let continuation = pending.removeValue(forKey: envelope.id) else { return }
            if status == "ok" {
                continuation.resume(
                    returning: BridgeResult(
                        id: envelope.id,
                        type: envelope.type,
                        payload: envelope.payload
                    )
                )
            } else {
                let data = try JSONEncoder().encode(envelope.payload)
                let remote = try JSONDecoder().decode(RemoteErrorPayload.self, from: data)
                continuation.resume(
                    throwing: BridgeClientError.remote(
                        code: remote.code,
                        message: remote.message,
                        recoverable: remote.recoverable
                    )
                )
            }
            return
        }
        eventContinuation.yield(
            BridgeEvent(id: envelope.id, type: envelope.type, payload: envelope.payload)
        )
    }

    private func failRequest(id: String, error: NWError) {
        pending.removeValue(forKey: id)?.resume(
            throwing: BridgeClientError.connectionFailed(error.localizedDescription)
        )
    }

    private func finish(_ error: BridgeClientError, terminateEvents: Bool) {
        guard connection != nil || isReady else { return }
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        isReady = false
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
        decoder = JsonLineDecoder()
        if terminateEvents {
            eventContinuation.finish(throwing: error)
        } else {
            eventContinuation.yield(
                BridgeEvent(
                    id: "transport-\(UUID().uuidString.lowercased())",
                    type: "transport.disconnected",
                    payload: .object([:])
                )
            )
        }
    }
}

private final class ConnectionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    init(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
    }

    func succeed() {
        resume(with: .success(()))
    }

    func fail(_ error: BridgeClientError) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, any Error>) {
        lock.lock()
        let active = continuation
        continuation = nil
        lock.unlock()
        active?.resume(with: result)
    }
}
