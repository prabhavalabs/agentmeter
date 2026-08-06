import AgentMeterCore
import AgentMeterIPC
import AgentMeterWidgetCore
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

private struct SettingsCommandResult: Decodable, Sendable {
    let syncStatus: String
    let settings: DeviceSettings?
}

@MainActor
@Observable
public final class AppModel {
    public private(set) var state: ControlState = .empty
    public private(set) var discoveredDevices: [PeripheralSummary] = []
    public private(set) var activeOperations: Set<AppOperation> = []
    public private(set) var bridgeReachable = false
    public private(set) var settingsSyncState: SettingsSyncState = .waitingForDevice
    public private(set) var pendingSettingsPatch: DeviceSettingsPatch?
    public private(set) var historySamples: [UsageHistorySample] = []
    public private(set) var historyRange: UsageHistoryRange = .last24Hours
    public private(set) var diagnostics: BridgeDiagnostics?
    public private(set) var requestedProviderDetailID: String?
    public var notice: AppNotice?

    public let preferences: AppPreferences

    @ObservationIgnored private let bridge: any BridgeAPI
    @ObservationIgnored private let widgetSnapshotCoordinator: any WidgetSnapshotCoordinating
    @ObservationIgnored private let widgetLocalDayScheduler: any WidgetLocalDayScheduling
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var widgetRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var widgetLocalDayTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored public var stateEventHandler:
        (@MainActor @Sendable (BridgeEvent, ControlState, ControlState) -> Void)?

    public init(
        bridge: any BridgeAPI,
        preferences: AppPreferences,
        widgetSnapshotCoordinator: any WidgetSnapshotCoordinating = NoopWidgetSnapshotCoordinator(),
        widgetLocalDayScheduler: any WidgetLocalDayScheduling = WidgetLocalDayScheduler()
    ) {
        self.bridge = bridge
        self.preferences = preferences
        self.widgetSnapshotCoordinator = widgetSnapshotCoordinator
        self.widgetLocalDayScheduler = widgetLocalDayScheduler
    }

    public var selectedSection: NavigationSection {
        get { preferences.selectedSection }
        set { preferences.selectedSection = newValue }
    }

    public var isBusy: Bool { !activeOperations.isEmpty }

    public func navigate(to route: AgentMeterRoute) {
        switch route {
        case .overview:
            selectedSection = .overview
        case .agents:
            selectedSection = .agents
        case let .provider(providerID):
            selectedSection = .overview
            requestedProviderDetailID = providerID
        }
    }

    public func completeRequestedProviderDetail(id: String) {
        guard requestedProviderDetailID == id else { return }
        requestedProviderDetailID = nil
    }

    public func start(showFailure: Bool = true) async {
        guard !hasStarted else { return }
        hasStarted = true
        await withOperation(.startup) {
            do {
                try await bridge.connect()
                bridgeReachable = true
                apply(try await bridge.status())
                listenForEvents()
                listenForWidgetLocalDayChanges()
                await loadSupplementalData()
                await widgetSnapshotCoordinator.refresh(state: state)
            } catch {
                bridgeReachable = false
                hasStarted = false
                if showFailure {
                    present(error, title: "Bridge unavailable")
                }
                scheduleReconnect()
            }
        }
    }

    public func stop() async {
        eventTask?.cancel()
        eventTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        widgetRefreshTask?.cancel()
        widgetRefreshTask = nil
        let localDayTask = widgetLocalDayTask
        widgetLocalDayTask = nil
        localDayTask?.cancel()
        await localDayTask?.value
        hasStarted = false
        bridgeReachable = false
        await bridge.close()
    }

    public func reconnect() async {
        eventTask?.cancel()
        eventTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
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
        await loadSupplementalData()
        await widgetSnapshotCoordinator.refresh(state: state)
    }

    public func patchSettings(_ patch: DeviceSettingsPatch) async {
        pendingSettingsPatch = patch
        settingsSyncState = .saving
        await withOperation(.settings) {
            do {
                let result = try await bridge.perform(.patchSettings(patch))
                let confirmed = try result.decodePayload(SettingsCommandResult.self)
                let previousSettings = state.settings
                if let settings = confirmed.settings {
                    applyConfirmedSettings(settings)
                }
                if widgetVisibilityChanged(from: previousSettings, to: state.settings) {
                    await invalidateWidgetSnapshot(.visibilityChanged)
                }
                pendingSettingsPatch = nil
                settingsSyncState = confirmed.syncStatus == "synced"
                    && confirmed.settings != nil
                    ? .synced
                    : .waitingForDevice
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

    public func setProviderOrder(_ providerIds: [String]) async {
        guard let settings = state.settings else { return }
        var patch = DeviceSettingsPatch(baseRevision: settings.revision)
        patch.providerOrder = providerIds
        await patchSettings(patch)
    }

    public func updateProviderCollection(ids: [String], pollIntervalSeconds: Int) async {
        await perform(
            .providerRefresh,
            command: .updateProviders(ids: ids, pollIntervalSeconds: pollIntervalSeconds)
        )
        await invalidateWidgetSnapshot(.visibilityChanged)
    }

    public func clearHistory() async {
        await withOperation(.diagnostics) {
            do {
                _ = try await bridge.perform(.clearHistory)
                apply(try await bridge.status())
                bridgeReachable = true
                historySamples = []
                await invalidateWidgetSnapshot(.historyCleared)
            } catch {
                present(error, title: "Action could not be completed")
            }
        }
    }

    public func loadHistory(
        _ range: UsageHistoryRange,
        now: Date = .now
    ) async {
        historyRange = range
        let query = range.query(now: now)
        do {
            let result = try await bridge.perform(
                .queryHistory(
                    sinceEpoch: query.sinceEpoch,
                    bucketSeconds: query.bucketSeconds,
                    currentCycle: query.currentCycle
                )
            )
            historySamples = try result.decodePayload(UsageHistoryResult.self).usage
        } catch {
            // Current status remains useful when optional history cannot be loaded.
        }
    }

    public func refreshDiagnostics() async {
        await withOperation(.diagnostics) {
            await loadDiagnostics(showFailure: true)
        }
    }

    public func systemWillSleep() async {
        await perform(.deviceConnection, command: .systemSleep, refreshAfterward: false)
    }

    public func systemDidWake() async {
        await perform(.deviceConnection, command: .systemWake)
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
                    guard let self else { return }
                    if event.type == "transport.disconnected" {
                        self.bridgeReachable = false
                        self.hasStarted = false
                        self.scheduleReconnect()
                        continue
                    }
                    let stateEventTypes: Set<String> = [
                        "state.changed", "connection.changed", "discovery.changed",
                        "providers.changed", "device.changed", "settings.changed",
                        "bridge.changed", "device.forgotten",
                    ]
                    guard stateEventTypes.contains(event.type) else { continue }
                    let incoming = try event.decodePayload(ControlState.self)
                    guard incoming.revision > self.state.revision else { continue }
                    let previous = self.state
                    self.apply(incoming)
                    self.stateEventHandler?(event, previous, incoming)
                    if self.widgetVisibilityChanged(
                        from: previous.settings,
                        to: incoming.settings
                    ) {
                        await self.invalidateWidgetSnapshot(
                            .visibilityChanged,
                            state: incoming
                        )
                    } else if event.type == "providers.changed" || event.type == "state.changed" {
                        self.scheduleWidgetRefresh(state: incoming)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                self?.bridgeReachable = false
                self?.hasStarted = false
                self?.present(error, title: "Bridge disconnected")
                self?.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            var delaySeconds = 2
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(delaySeconds))
                guard Task.isCancelled == false, let self else { return }
                await self.start(showFailure: false)
                if self.bridgeReachable {
                    self.reconnectTask = nil
                    return
                }
                delaySeconds = min(delaySeconds * 2, 30)
            }
        }
    }

    private func listenForWidgetLocalDayChanges() {
        guard widgetLocalDayTask == nil else { return }
        let scheduler = widgetLocalDayScheduler
        widgetLocalDayTask = Task { [weak self] in
            while Task.isCancelled == false {
                do {
                    try await scheduler.waitForNextLocalDay()
                } catch {
                    return
                }
                guard Task.isCancelled == false, let self else { return }
                self.scheduleWidgetRefresh(state: self.state)
            }
        }
    }

    private func apply(_ incoming: ControlState) {
        guard incoming.revision >= state.revision else { return }
        state = incoming
        discoveredDevices = incoming.peripherals
        bridgeReachable = incoming.bridge.running
        if pendingSettingsPatch == nil {
            updateSettingsSyncState()
        }
    }

    private func applyConfirmedSettings(_ settings: DeviceSettings) {
        if let current = state.settings, settings.revision < current.revision {
            return
        }
        state = ControlState(
            revision: state.revision,
            connection: state.connection,
            peripherals: state.peripherals,
            information: state.information,
            telemetry: state.telemetry,
            settings: settings,
            providers: state.providers,
            bridge: state.bridge
        )
    }

    private func widgetVisibilityChanged(
        from previous: DeviceSettings?,
        to current: DeviceSettings?
    ) -> Bool {
        previous?.hiddenProviderIds != current?.hiddenProviderIds
            || previous?.providerOrder != current?.providerOrder
    }

    private func scheduleWidgetRefresh(state: ControlState) {
        widgetRefreshTask?.cancel()
        let coordinator = widgetSnapshotCoordinator
        widgetRefreshTask = Task {
            await coordinator.refresh(state: state)
        }
    }

    private func invalidateWidgetSnapshot(
        _ invalidation: WidgetSnapshotInvalidation,
        state publicationState: ControlState? = nil
    ) async {
        widgetRefreshTask?.cancel()
        widgetRefreshTask = nil
        let publicationState = publicationState ?? state
        await widgetSnapshotCoordinator.invalidate(
            state: publicationState,
            invalidation: invalidation
        )
        scheduleWidgetRefresh(state: publicationState)
    }

    private func updateSettingsSyncState() {
        let connection = state.connection
        settingsSyncState = connection.phase == .connected
            && connection.managementAvailable == true
            && state.settings != nil
            ? .synced
            : .waitingForDevice
    }

    private func loadSupplementalData() async {
        await loadHistory(historyRange)
        await loadDiagnostics(showFailure: false)
    }

    private func loadDiagnostics(showFailure: Bool) async {
        do {
            let result = try await bridge.perform(.diagnostics)
            diagnostics = try result.decodePayload(BridgeDiagnostics.self)
        } catch {
            if showFailure { present(error, title: "Diagnostics unavailable") }
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
