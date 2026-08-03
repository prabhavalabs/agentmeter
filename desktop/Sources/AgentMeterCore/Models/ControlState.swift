import Foundation

public struct BridgeStatus: Codable, Equatable, Sendable {
    public let version: String
    public let running: Bool
    public let lastProviderRefreshEpoch: Int?
    public let lastDeviceSyncEpoch: Int?
    public let lastErrorCode: String?
    public let providerHealth: [String: String]

    public init(
        version: String,
        running: Bool,
        lastProviderRefreshEpoch: Int? = nil,
        lastDeviceSyncEpoch: Int? = nil,
        lastErrorCode: String? = nil,
        providerHealth: [String: String] = [:]
    ) {
        self.version = version
        self.running = running
        self.lastProviderRefreshEpoch = lastProviderRefreshEpoch
        self.lastDeviceSyncEpoch = lastDeviceSyncEpoch
        self.lastErrorCode = lastErrorCode
        self.providerHealth = providerHealth
    }
}

public struct ControlState: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let connection: ConnectionState
    public let peripherals: [PeripheralSummary]
    public let information: DeviceInformation?
    public let telemetry: DeviceTelemetry?
    public let settings: DeviceSettings?
    public let providers: [ProviderSummary]
    public let bridge: BridgeStatus

    public init(
        revision: UInt64,
        connection: ConnectionState,
        peripherals: [PeripheralSummary] = [],
        information: DeviceInformation? = nil,
        telemetry: DeviceTelemetry? = nil,
        settings: DeviceSettings? = nil,
        providers: [ProviderSummary] = [],
        bridge: BridgeStatus
    ) {
        self.revision = revision
        self.connection = connection
        self.peripherals = peripherals
        self.information = information
        self.telemetry = telemetry
        self.settings = settings
        self.providers = providers
        self.bridge = bridge
    }

    public static let empty = ControlState(
        revision: 0,
        connection: ConnectionState(phase: .stopped),
        bridge: BridgeStatus(version: "0.1.0", running: false)
    )
}

public struct StatusEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let type: String
    public let status: String
    public let payload: ControlState
}
