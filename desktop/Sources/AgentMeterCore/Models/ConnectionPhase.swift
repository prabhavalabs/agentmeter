import Foundation

public enum ConnectionPhase: String, Codable, CaseIterable, Sendable {
    case stopped
    case bluetoothUnavailable
    case searching
    case connecting
    case authenticating
    case synchronizing
    case connected
    case degraded
    case retrying

    public var isBusy: Bool {
        switch self {
        case .searching, .connecting, .authenticating, .synchronizing, .retrying:
            true
        default:
            false
        }
    }
}

public struct ConnectionState: Codable, Equatable, Sendable {
    public let phase: ConnectionPhase
    public let selectedDeviceId: String?
    public let selectedDeviceName: String?
    public let rssi: Int?
    public let managementAvailable: Bool?
    public let nextRetryEpoch: Int?
    public let errorCode: String?

    public init(
        phase: ConnectionPhase,
        selectedDeviceId: String? = nil,
        selectedDeviceName: String? = nil,
        rssi: Int? = nil,
        managementAvailable: Bool? = nil,
        nextRetryEpoch: Int? = nil,
        errorCode: String? = nil
    ) {
        self.phase = phase
        self.selectedDeviceId = selectedDeviceId
        self.selectedDeviceName = selectedDeviceName
        self.rssi = rssi
        self.managementAvailable = managementAvailable
        self.nextRetryEpoch = nextRetryEpoch
        self.errorCode = errorCode
    }
}
