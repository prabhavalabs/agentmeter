import Foundation

public struct PeripheralSummary: Codable, Equatable, Identifiable, Sendable {
    public let identifier: String
    public let name: String
    public let rssi: Int?
    public let lastSeenEpoch: Int?

    public var id: String { identifier }

    public init(identifier: String, name: String, rssi: Int?, lastSeenEpoch: Int?) {
        self.identifier = identifier
        self.name = name
        self.rssi = rssi
        self.lastSeenEpoch = lastSeenEpoch
    }
}

public struct DeviceCapabilities: Codable, Equatable, Sendable {
    public let settings: Bool
    public let identify: Bool
    public let restart: Bool
    public let forget: Bool
    public let brightness: Bool
    public let battery: Bool
    public let vbusVoltage: Bool
    public let inputCurrent: Bool

    public init(
        settings: Bool,
        identify: Bool,
        restart: Bool,
        forget: Bool,
        brightness: Bool,
        battery: Bool,
        vbusVoltage: Bool,
        inputCurrent: Bool
    ) {
        self.settings = settings
        self.identify = identify
        self.restart = restart
        self.forget = forget
        self.brightness = brightness
        self.battery = battery
        self.vbusVoltage = vbusVoltage
        self.inputCurrent = inputCurrent
    }
}

public struct DeviceInformation: Codable, Equatable, Sendable {
    public let model: String
    public let name: String
    public let firmwareVersion: String
    public let hardwareRevision: String
    public let snapshotSchemaVersion: Int
    public let managementSchemaVersion: Int
    public let capabilities: DeviceCapabilities

    public init(
        model: String,
        name: String,
        firmwareVersion: String,
        hardwareRevision: String,
        snapshotSchemaVersion: Int,
        managementSchemaVersion: Int,
        capabilities: DeviceCapabilities
    ) {
        self.model = model
        self.name = name
        self.firmwareVersion = firmwareVersion
        self.hardwareRevision = hardwareRevision
        self.snapshotSchemaVersion = snapshotSchemaVersion
        self.managementSchemaVersion = managementSchemaVersion
        self.capabilities = capabilities
    }
}

public struct DeviceTelemetry: Codable, Equatable, Sendable {
    public let powerSource: String?
    public let usbPresent: Bool?
    public let batteryPresent: Bool?
    public let charging: Bool?
    public let batteryPercent: Int?
    public let batteryVoltageMv: Int?
    public let vbusVoltageMv: Int?
    public let inputCurrentMa: Int?
    public let uptimeSeconds: Int?
    public let freeHeapBytes: Int?
    public let minimumFreeHeapBytes: Int?
    public let displayOn: Bool?
    public let displayDimmed: Bool?
    public let brightnessPercent: Int?
    public let boardTemperatureC: Double?

    public init(
        powerSource: String? = nil,
        usbPresent: Bool? = nil,
        batteryPresent: Bool? = nil,
        charging: Bool? = nil,
        batteryPercent: Int? = nil,
        batteryVoltageMv: Int? = nil,
        vbusVoltageMv: Int? = nil,
        inputCurrentMa: Int? = nil,
        uptimeSeconds: Int? = nil,
        freeHeapBytes: Int? = nil,
        minimumFreeHeapBytes: Int? = nil,
        displayOn: Bool? = nil,
        displayDimmed: Bool? = nil,
        brightnessPercent: Int? = nil,
        boardTemperatureC: Double? = nil
    ) {
        self.powerSource = powerSource
        self.usbPresent = usbPresent
        self.batteryPresent = batteryPresent
        self.charging = charging
        self.batteryPercent = batteryPercent
        self.batteryVoltageMv = batteryVoltageMv
        self.vbusVoltageMv = vbusVoltageMv
        self.inputCurrentMa = inputCurrentMa
        self.uptimeSeconds = uptimeSeconds
        self.freeHeapBytes = freeHeapBytes
        self.minimumFreeHeapBytes = minimumFreeHeapBytes
        self.displayOn = displayOn
        self.displayDimmed = displayDimmed
        self.brightnessPercent = brightnessPercent
        self.boardTemperatureC = boardTemperatureC
    }
}
