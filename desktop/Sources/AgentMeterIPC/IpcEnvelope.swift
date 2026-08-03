import AgentMeterCore
import Foundation

public enum BridgeClientError: Error, Equatable, LocalizedError, Sendable {
    case notConnected
    case connectionFailed(String)
    case disconnected
    case invalidFrame
    case frameTooLarge
    case remote(code: String, message: String, recoverable: Bool)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "The AgentMeter bridge is not connected."
        case let .connectionFailed(message): message
        case .disconnected: "The AgentMeter bridge disconnected."
        case .invalidFrame: "The bridge returned an invalid message."
        case .frameTooLarge: "The bridge returned an oversized message."
        case let .remote(_, message, _): message
        }
    }
}

struct IpcRequestEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let id: String
    let type: String
    let payload: [String: JSONValue]

    init(
        schemaVersion: Int = 1,
        id: String,
        type: String,
        payload: [String: JSONValue]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.type = type
        self.payload = payload
    }
}

struct IncomingEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let id: String
    let type: String
    let status: String?
    let payload: JSONValue
}

public struct BridgeResult: Equatable, Sendable {
    public let id: String
    public let type: String
    public let payload: JSONValue

    public init(id: String, type: String, payload: JSONValue) {
        self.id = id
        self.type = type
        self.payload = payload
    }

    public func decodePayload<T: Decodable & Sendable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(type, from: data)
    }
}

public struct BridgeEvent: Equatable, Sendable {
    public let id: String
    public let type: String
    public let payload: JSONValue

    public init(id: String, type: String, payload: JSONValue) {
        self.id = id
        self.type = type
        self.payload = payload
    }

    public func decodePayload<T: Decodable & Sendable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(type, from: data)
    }
}

struct RemoteErrorPayload: Codable, Sendable {
    let code: String
    let message: String
    let recoverable: Bool
}
