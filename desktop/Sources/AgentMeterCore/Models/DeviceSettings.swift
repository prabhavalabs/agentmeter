import Foundation

public struct DeviceSettings: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let alwaysOn: Bool
    public let fullView: Bool
    public let rotationSeconds: Int
    public let brightnessPercent: Int
    public let dimAfterSeconds: Int
    public let screenOffAfterSeconds: Int
    public let alertThresholds: [Int]
    public let soundEnabled: Bool
    public let hiddenProviderIds: [String]
    public let providerOrder: [String]

    public init(
        revision: UInt64,
        alwaysOn: Bool,
        fullView: Bool,
        rotationSeconds: Int,
        brightnessPercent: Int,
        dimAfterSeconds: Int,
        screenOffAfterSeconds: Int,
        alertThresholds: [Int],
        soundEnabled: Bool,
        hiddenProviderIds: [String],
        providerOrder: [String]
    ) {
        self.revision = revision
        self.alwaysOn = alwaysOn
        self.fullView = fullView
        self.rotationSeconds = rotationSeconds
        self.brightnessPercent = brightnessPercent
        self.dimAfterSeconds = dimAfterSeconds
        self.screenOffAfterSeconds = screenOffAfterSeconds
        self.alertThresholds = alertThresholds
        self.soundEnabled = soundEnabled
        self.hiddenProviderIds = hiddenProviderIds
        self.providerOrder = providerOrder
    }
}

public struct DeviceSettingsPatch: Codable, Equatable, Sendable {
    public var baseRevision: UInt64
    public var alwaysOn: Bool?
    public var fullView: Bool?
    public var rotationSeconds: Int?
    public var brightnessPercent: Int?
    public var dimAfterSeconds: Int?
    public var screenOffAfterSeconds: Int?
    public var alertThresholds: [Int]?
    public var soundEnabled: Bool?
    public var hiddenProviderIds: [String]?
    public var providerOrder: [String]?

    public init(baseRevision: UInt64) {
        self.baseRevision = baseRevision
    }
}
