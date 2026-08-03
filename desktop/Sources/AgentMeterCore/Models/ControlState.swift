import Foundation

public struct BridgeStatus: Codable, Equatable, Sendable {
    public let version: String
    public let running: Bool
    public let lastProviderRefreshEpoch: Int?
    public let lastDeviceSyncEpoch: Int?
    public let lastErrorCode: String?
    public let providerHealth: [String: String]
    public let configuredProviderIds: [String]
    public let pollIntervalSeconds: Int

    public init(
        version: String,
        running: Bool,
        lastProviderRefreshEpoch: Int? = nil,
        lastDeviceSyncEpoch: Int? = nil,
        lastErrorCode: String? = nil,
        providerHealth: [String: String] = [:],
        configuredProviderIds: [String] = [],
        pollIntervalSeconds: Int = 300
    ) {
        self.version = version
        self.running = running
        self.lastProviderRefreshEpoch = lastProviderRefreshEpoch
        self.lastDeviceSyncEpoch = lastDeviceSyncEpoch
        self.lastErrorCode = lastErrorCode
        self.providerHealth = providerHealth
        self.configuredProviderIds = configuredProviderIds
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case version, running, lastProviderRefreshEpoch, lastDeviceSyncEpoch, lastErrorCode
        case providerHealth, configuredProviderIds, pollIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        running = try values.decode(Bool.self, forKey: .running)
        lastProviderRefreshEpoch = try values.decodeIfPresent(Int.self, forKey: .lastProviderRefreshEpoch)
        lastDeviceSyncEpoch = try values.decodeIfPresent(Int.self, forKey: .lastDeviceSyncEpoch)
        lastErrorCode = try values.decodeIfPresent(String.self, forKey: .lastErrorCode)
        providerHealth = try values.decodeIfPresent([String: String].self, forKey: .providerHealth) ?? [:]
        configuredProviderIds = try values.decodeIfPresent([String].self, forKey: .configuredProviderIds) ?? []
        pollIntervalSeconds = try values.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 300
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
        bridge: BridgeStatus(version: "Unavailable", running: false)
    )
}

public struct StatusEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let type: String
    public let status: String
    public let payload: ControlState
}
