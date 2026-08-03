import Foundation

public struct DiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    public let type: String
    public let revision: UInt64
    public let occurredAtEpoch: Int

    public var id: String { "\(revision):\(type):\(occurredAtEpoch)" }

    public init(type: String, revision: UInt64, occurredAtEpoch: Int) {
        self.type = type
        self.revision = revision
        self.occurredAtEpoch = occurredAtEpoch
    }
}

public struct BridgeDiagnostics: Codable, Equatable, Sendable {
    public let bridgeVersion: String
    public let ipcSchemaVersion: Int
    public let phase: String
    public let managementAvailable: Bool?
    public let providerHealth: [String: String]
    public let recentEvents: [DiagnosticEvent]

    public init(
        bridgeVersion: String,
        ipcSchemaVersion: Int,
        phase: String,
        managementAvailable: Bool?,
        providerHealth: [String: String],
        recentEvents: [DiagnosticEvent]
    ) {
        self.bridgeVersion = bridgeVersion
        self.ipcSchemaVersion = ipcSchemaVersion
        self.phase = phase
        self.managementAvailable = managementAvailable
        self.providerHealth = providerHealth
        self.recentEvents = recentEvents
    }
}
