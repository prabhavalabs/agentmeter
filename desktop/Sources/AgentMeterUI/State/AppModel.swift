import AgentMeterCore
import AgentMeterIPC
import Foundation
import Observation

public enum AppOperation: String, Hashable, Sendable {
    case startup
    case scanning
    case deviceConnection
    case identify
    case providerRefresh
    case settings
    case diagnostics
    case bridgeRestart
}

public enum SettingsSyncState: Equatable, Sendable {
    case synced
    case saving
    case waitingForDevice
}

public struct AppNotice: Equatable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case information
        case warning
        case error
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let message: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
    }
}

@MainActor
@Observable
public final class AppModel {
    public private(set) var state: ControlState = .empty
    public private(set) var discoveredDevices: [PeripheralSummary] = []
    public private(set) var activeOperations: Set<AppOperation> = []
    public private(set) var bridgeReachable = false
    public private(set) var settingsSyncState: SettingsSyncState = .synced
    public private(set) var pendingSettingsPatch: DeviceSettingsPatch?
    public var notice: AppNotice?

    public let preferences: AppPreferences

    @ObservationIgnored private let bridge: any BridgeAPI
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false

    public init(bridge: any BridgeAPI, preferences: AppPreferences) {
        self.bridge = bridge
        self.preferences = preferences
    }

    public var selectedSection: NavigationSection {
        get { preferences.selectedSection }
        set { preferences.selectedSection = newValue }
    }

    public var isBusy: Bool { !activeOperations.isEmpty }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await withOperation(.startup) {
            do {
                try await bridge.connect()
                bridgeReachable = true
                apply(try await bridge.status())
                listenForEvents()
            } catch {
                bridgeReachable = false
                hasStarted = false
                present(error, title: "Bridge unavailable")
            }
        }
    }

    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        hasStarted = false
        bridgeReachable = false
        await bridge.close()
    }

    public func reconnect() async {
        eventTask?.cancel()
        eventTask = nil
        hasStarted = false
        await start()
        guard bridgeReachable else { return }
        await perform(.deviceConnection, command: .connectDevice(identifier: nil))
    }

    public func scan() async {
        await withOperation(.scanning) {
            do {
                discoveredDevices = try await bridge.scan()
                bridgeReachable = true
            } catch {
                present(error, title: "Scan failed")
            }
        }
    }

    public func connect(to identifier: String) async {
        await perform(.deviceConnection, command: .connectDevice(identifier: identifier))
    }

    public func disconnect() async {
        await perform(.deviceConnection, command: .disconnectDevice)
    }

    public func forgetDevice() async {
        await perform(.deviceConnection, command: .forgetDevice)
    }

    public func identifyDevice() async {
        await perform(.identify, command: .identifyDevice)
    }

    public func refreshDevice() async {
        await perform(.deviceConnection, command: .refreshDevice)
    }

    public func refreshProviders() async {
        await perform(.providerRefresh, command: .refreshProviders)
    }

    public func patchSettings(_ patch: DeviceSettingsPatch) async {
        pendingSettingsPatch = patch
        settingsSyncState = .saving
        await withOperation(.settings) {
            do {
                _ = try await bridge.perform(.patchSettings(patch))
                apply(try await bridge.status())
                pendingSettingsPatch = nil
                settingsSyncState = .synced
            } catch let error as BridgeClientError {
                if case let .remote(code, _, _) = error, code == "revisionConflict" {
                    settingsSyncState = .waitingForDevice
                    present(error, title: "Settings changed on the device")
                } else {
                    settingsSyncState = .waitingForDevice
                    present(error, title: "Settings not saved")
                }
            } catch {
                settingsSyncState = .waitingForDevice
                present(error, title: "Settings not saved")
            }
        }
    }

    public func reorderProviders(from offsets: IndexSet, to destination: Int) async {
        guard let settings = state.settings else { return }
        var order = settings.providerOrder
        let moving = offsets.compactMap { order.indices.contains($0) ? order[$0] : nil }
        for offset in offsets.sorted(by: >) where order.indices.contains(offset) {
            order.remove(at: offset)
        }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            order.endIndex
        )
        order.insert(contentsOf: moving, at: insertionIndex)
        var patch = DeviceSettingsPatch(baseRevision: settings.revision)
        patch.providerOrder = order
        await patchSettings(patch)
    }

    public func updateProviderCollection(ids: [String], pollIntervalSeconds: Int) async {
        await perform(
            .providerRefresh,
            command: .updateProviders(ids: ids, pollIntervalSeconds: pollIntervalSeconds)
        )
    }

    public func clearHistory() async {
        await perform(.diagnostics, command: .clearHistory)
    }

    public func restartBridge() async {
        await perform(.bridgeRestart, command: .restartBridge, refreshAfterward: false)
    }

    public func dismissNotice() {
        notice = nil
    }

    private func perform(
        _ operation: AppOperation,
        command: BridgeCommand,
        refreshAfterward: Bool = true
    ) async {
        await withOperation(operation) {
            do {
                _ = try await bridge.perform(command)
                if refreshAfterward {
                    apply(try await bridge.status())
                }
                bridgeReachable = true
            } catch {
                present(error, title: "Action could not be completed")
            }
        }
    }

    private func withOperation(
        _ operation: AppOperation,
        action: () async -> Void
    ) async {
        guard activeOperations.contains(operation) == false else { return }
        activeOperations.insert(operation)
        defer { activeOperations.remove(operation) }
        await action()
    }

    private func listenForEvents() {
        guard eventTask == nil else { return }
        let stream = bridge.events()
        eventTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard Task.isCancelled == false else { return }
                    guard event.type == "state.changed" else { continue }
                    guard let self else { return }
                    let incoming = try event.decodePayload(ControlState.self)
                    guard incoming.revision > self.state.revision else { continue }
                    self.apply(incoming)
                }
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                self?.bridgeReachable = false
                self?.hasStarted = false
                self?.present(error, title: "Bridge disconnected")
            }
        }
    }

    private func apply(_ incoming: ControlState) {
        guard incoming.revision >= state.revision else { return }
        state = incoming
        discoveredDevices = incoming.peripherals
        bridgeReachable = incoming.bridge.running
        if pendingSettingsPatch == nil {
            settingsSyncState = .synced
        }
    }

    private func present(_ error: Error, title: String) {
        notice = AppNotice(
            kind: .error,
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }
}
