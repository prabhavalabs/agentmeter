import AgentMeterCore
import AgentMeterIPC
import AgentMeterWidgetCore
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public protocol WidgetSnapshotCoordinating: Sendable {
    func refresh(state: ControlState) async
}

public protocol WidgetTimelineReloading: Sendable {
    func reloadWidgetTimelines() async
}

public struct NoopWidgetSnapshotCoordinator: WidgetSnapshotCoordinating {
    public init() {}

    public func refresh(state _: ControlState) async {}
}

public struct WidgetKitTimelineReloader: WidgetTimelineReloading {
    public init() {}

    public func reloadWidgetTimelines() async {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.dashboard.rawValue)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.focus.rawValue)
        #endif
    }
}

public actor WidgetSnapshotCoordinator: WidgetSnapshotCoordinating {
    private let bridge: any BridgeAPI
    private let store: WidgetSnapshotStore
    private let reloader: any WidgetTimelineReloading
    private let calendarProvider: @Sendable () -> Calendar
    private let now: @Sendable () -> Date

    private var cachedSummaries: [String: WidgetHistorySummary] = [:]
    private var refreshGeneration: UInt64 = 0

    public init(
        bridge: any BridgeAPI,
        store: WidgetSnapshotStore,
        reloader: any WidgetTimelineReloading,
        calendar: Calendar? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.bridge = bridge
        self.store = store
        self.reloader = reloader
        self.now = now
        if let calendar {
            calendarProvider = { calendar }
        } else {
            calendarProvider = {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                return calendar
            }
        }
    }

    public init(
        bridge: any BridgeAPI,
        directoryURL: URL,
        reloader: any WidgetTimelineReloading,
        calendar: Calendar? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.init(
            bridge: bridge,
            store: WidgetSnapshotStore(directoryURL: directoryURL),
            reloader: reloader,
            calendar: calendar,
            now: now
        )
    }

    public func refresh(state: ControlState) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let publicationState = stateForPublication(from: state)
        let providerIds = publicationState.providers.map(\.id)
        let calendar = currentGregorianCalendar()
        let today = calendar.startOfDay(for: now())
        guard let historyStart = calendar.date(
            byAdding: .day,
            value: -(WidgetSnapshot.maximumHistoryDayCount - 1),
            to: today
        ) else { return }
        let sinceEpoch = max(0, Int(historyStart.timeIntervalSince1970))
        let timeZoneIdentifier = calendar.timeZone.identifier

        for providerId in providerIds {
            do {
                let result = try await bridge.perform(
                    .queryWidgetHistory(
                        sinceEpoch: sinceEpoch,
                        providerId: providerId,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
                let summary = try result.decodePayload(WidgetHistorySummary.self)
                guard generation == refreshGeneration else { return }
                cachedSummaries[providerId] = summary
            } catch {
                guard generation == refreshGeneration else { return }
            }
        }
        guard generation == refreshGeneration else { return }

        let summaries = Dictionary(
            uniqueKeysWithValues: providerIds.compactMap { providerId in
                cachedSummaries[providerId].map { (providerId, $0) }
            }
        )
        do {
            let snapshot = try WidgetSnapshotBuilder().build(
                state: publicationState,
                summaries: summaries
            )
            guard try store.writeIfChanged(snapshot) else { return }
            await reloader.reloadWidgetTimelines()
        } catch {
            // Widget publication is supplemental; the live application state remains authoritative.
        }
    }

    private func currentGregorianCalendar() -> Calendar {
        let configured = calendarProvider()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configured.timeZone
        return calendar
    }

    private func stateForPublication(from state: ControlState) -> ControlState {
        let hidden = Set(state.settings?.hiddenProviderIds ?? [])
        let visible = state.providers.filter { hidden.contains($0.id) == false }
        let configuredOrder: [String]
        if let settingsOrder = state.settings?.providerOrder, settingsOrder.isEmpty == false {
            configuredOrder = settingsOrder
        } else if state.bridge.configuredProviderIds.isEmpty == false {
            configuredOrder = state.bridge.configuredProviderIds
        } else {
            configuredOrder = visible.map(\.id)
        }

        let providersById = Dictionary(
            visible.reversed().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let configured = configuredOrder.compactMap { id -> ProviderSummary? in
            guard seen.insert(id).inserted else { return nil }
            return providersById[id]
        }
        let remaining = visible.filter { seen.insert($0.id).inserted }
        let selected = Array((configured + remaining).prefix(WidgetSnapshot.maximumProviderCount))

        return ControlState(
            revision: state.revision,
            connection: state.connection,
            peripherals: state.peripherals,
            information: state.information,
            telemetry: state.telemetry,
            settings: state.settings,
            providers: selected,
            bridge: state.bridge
        )
    }
}
