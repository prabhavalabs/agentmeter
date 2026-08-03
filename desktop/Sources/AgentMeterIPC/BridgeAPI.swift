import AgentMeterCore
import Foundation

public protocol BridgeAPI: Sendable {
    func connect() async throws
    func status() async throws -> ControlState
    func scan() async throws -> [PeripheralSummary]
    func perform(_ command: BridgeCommand) async throws -> BridgeResult
    func events() -> AsyncThrowingStream<BridgeEvent, Error>
    func close() async
}

public enum BridgeCommand: Sendable {
    case connectDevice(identifier: String?)
    case disconnectDevice
    case forgetDevice
    case identifyDevice
    case refreshDevice
    case getSettings
    case patchSettings(DeviceSettingsPatch)
    case refreshProviders
    case updateProviders(ids: [String], pollIntervalSeconds: Int)
    case queryHistory(sinceEpoch: Int, providerId: String? = nil)
    case clearHistory
    case diagnostics
    case restartBridge
    case systemSleep
    case systemWake

    var messageType: String {
        switch self {
        case .connectDevice: "device.connect"
        case .disconnectDevice: "device.disconnect"
        case .forgetDevice: "device.forget"
        case .identifyDevice: "device.identify"
        case .refreshDevice: "device.refresh"
        case .getSettings: "settings.get"
        case .patchSettings: "settings.patch"
        case .refreshProviders: "providers.refresh"
        case .updateProviders: "providers.update"
        case .queryHistory: "history.query"
        case .clearHistory: "history.clear"
        case .diagnostics: "diagnostics.get"
        case .restartBridge: "bridge.restart"
        case .systemSleep: "system.sleep"
        case .systemWake: "system.wake"
        }
    }

    func payload() throws -> [String: JSONValue] {
        switch self {
        case let .connectDevice(identifier):
            guard let identifier else { return [:] }
            return ["identifier": .string(identifier)]
        case let .patchSettings(patch):
            guard case let .object(payload) = try patch.jsonValue() else {
                throw BridgeClientError.invalidFrame
            }
            return payload
        case let .updateProviders(ids, interval):
            return [
                "providerIds": .array(ids.map(JSONValue.string)),
                "pollIntervalSeconds": .integer(interval),
            ]
        case let .queryHistory(sinceEpoch, providerId):
            var payload: [String: JSONValue] = ["sinceEpoch": .integer(sinceEpoch)]
            if let providerId { payload["providerId"] = .string(providerId) }
            return payload
        default:
            return [:]
        }
    }
}

struct PeripheralResult: Codable, Sendable {
    let peripherals: [PeripheralSummary]
}
