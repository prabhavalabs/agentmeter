import AgentMeterCore
import AgentMeterIPC
import AgentMeterWidgetCore
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public protocol WidgetSnapshotCoordinating: Sendable {
    func refresh(state: ControlState) async
    func invalidate(
        state: ControlState,
        invalidation: WidgetSnapshotInvalidation
    ) async
}

public extension WidgetSnapshotCoordinating {
    func invalidateAndRefresh(
        state: ControlState,
        invalidation: WidgetSnapshotInvalidation
    ) async {
        await invalidate(state: state, invalidation: invalidation)
        await refresh(state: state)
    }
}

public enum WidgetSnapshotInvalidation: Equatable, Sendable {
    case visibilityChanged
    case historyCleared
}

public protocol WidgetTimelineReloading: Sendable {
    func reloadWidgetTimelines() async
}

public protocol WidgetTimelineKindReloading: Sendable {
    func reloadTimelines(ofKind kind: String) async
}

public struct WidgetCenterTimelineReloadSink: WidgetTimelineKindReloading {
    public init() {}

    public func reloadTimelines(ofKind kind: String) async {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}

public struct NoopWidgetSnapshotCoordinator: WidgetSnapshotCoordinating {
    public init() {}

    public func refresh(state _: ControlState) async {}

    public func invalidate(
        state _: ControlState,
        invalidation _: WidgetSnapshotInvalidation
    ) async {}
}

public struct WidgetKitTimelineReloader: WidgetTimelineReloading {
    private let sink: any WidgetTimelineKindReloading

    public init() {
        sink = WidgetCenterTimelineReloadSink()
    }

    public init(sink: any WidgetTimelineKindReloading) {
        self.sink = sink
    }

    public func reloadWidgetTimelines() async {
        for kind in WidgetKind.allCases {
            await sink.reloadTimelines(ofKind: kind.rawValue)
        }
    }
}

public actor WidgetSnapshotCoordinator: WidgetSnapshotCoordinating {
    private let bridge: any BridgeAPI
    private let store: WidgetSnapshotStore
    private let reloader: any WidgetTimelineReloading
    private let calendarProvider: @Sendable () -> Calendar
    private let now: @Sendable () -> Date

    private var cachedSummaries: [String: WidgetHistorySummary] = [:]
    private var cachedTimeZoneIdentifier: String?
    private var refreshGeneration: UInt64 = 0

    public init(
        bridge: any BridgeAPI,
        store: WidgetSnapshotStore,
        reloader: any WidgetTimelineReloading,
        calendar: Calendar? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let provider: @Sendable () -> Calendar
        if let calendar {
            provider = { calendar }
        } else {
            provider = {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                return calendar
            }
        }
        self.init(
            bridge: bridge,
            store: store,
            reloader: reloader,
            calendarProvider: provider,
            now: now
        )
    }

    public init(
        bridge: any BridgeAPI,
        store: WidgetSnapshotStore,
        reloader: any WidgetTimelineReloading,
        calendarProvider: @escaping @Sendable () -> Calendar,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.bridge = bridge
        self.store = store
        self.reloader = reloader
        self.calendarProvider = calendarProvider
        self.now = now
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
        await performRefresh(state: state)
    }

    public func invalidate(
        state: ControlState,
        invalidation: WidgetSnapshotInvalidation
    ) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard let publication = preparePublication(
            state: state,
            invalidation: invalidation
        ) else { return }
        _ = await publish(
            state: publication.state,
            providerIds: publication.providerIds,
            generation: generation
        )
    }

    private func performRefresh(state: ControlState) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard let publication = preparePublication(state: state, invalidation: nil) else { return }
        let publicationState = publication.state
        let providerIds = publication.providerIds
        let sinceEpoch = publication.sinceEpoch
        let timeZoneIdentifier = publication.timeZoneIdentifier

        for providerId in providerIds {
            guard Task.isCancelled == false else { return }
            do {
                let result = try await bridge.perform(
                    .queryWidgetHistory(
                        sinceEpoch: sinceEpoch,
                        providerId: providerId,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                )
                let summary = try result.decodePayload(WidgetHistorySummary.self)
                guard Task.isCancelled == false, generation == refreshGeneration else { return }
                cachedSummaries[providerId] = clipped(summary, sinceEpoch: sinceEpoch)
            } catch {
                guard Task.isCancelled == false, generation == refreshGeneration else { return }
            }
        }
        guard Task.isCancelled == false, generation == refreshGeneration else { return }

        _ = await publish(
            state: publicationState,
            providerIds: providerIds,
            generation: generation
        )
    }

    private func preparePublication(
        state: ControlState,
        invalidation: WidgetSnapshotInvalidation?
    ) -> (
        state: ControlState,
        providerIds: [String],
        sinceEpoch: Int,
        timeZoneIdentifier: String
    )? {
        let publicationState = stateForPublication(from: state)
        let providerIds = publicationState.providers.map(\.id)
        let calendar = currentGregorianCalendar()
        let today = calendar.startOfDay(for: now())
        guard let historyStart = calendar.date(
            byAdding: .day,
            value: -(WidgetSnapshot.maximumHistoryDayCount - 1),
            to: today
        ) else { return nil }
        let sinceEpoch = max(0, Int(historyStart.timeIntervalSince1970))
        let timeZoneIdentifier = calendar.timeZone.identifier
        if cachedTimeZoneIdentifier != timeZoneIdentifier {
            cachedSummaries.removeAll()
            cachedTimeZoneIdentifier = timeZoneIdentifier
        }
        if invalidation == .historyCleared {
            cachedSummaries.removeAll()
        }
        cachedSummaries = Dictionary(
            uniqueKeysWithValues: providerIds.compactMap { providerId in
                cachedSummaries[providerId].map {
                    (providerId, clipped($0, sinceEpoch: sinceEpoch))
                }
            }
        )
        return (
            state: publicationState,
            providerIds: providerIds,
            sinceEpoch: sinceEpoch,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func publish(
        state: ControlState,
        providerIds: [String],
        generation: UInt64
    ) async -> Bool {
        guard Task.isCancelled == false, generation == refreshGeneration else { return false }
        let summaries = Dictionary(
            uniqueKeysWithValues: providerIds.compactMap { providerId in
                cachedSummaries[providerId].map { (providerId, $0) }
            }
        )
        do {
            let snapshot = try WidgetSnapshotBuilder().build(
                state: state,
                summaries: summaries
            )
            guard Task.isCancelled == false, generation == refreshGeneration else { return false }
            if try store.writeIfChanged(snapshot) {
                await reloader.reloadWidgetTimelines()
            }
        } catch {
            // Widget publication is supplemental; the live application state remains authoritative.
            return false
        }
        return Task.isCancelled == false && generation == refreshGeneration
    }

    private func currentGregorianCalendar() -> Calendar {
        let configured = calendarProvider()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = configured.timeZone
        return calendar
    }

    private func clipped(
        _ summary: WidgetHistorySummary,
        sinceEpoch: Int
    ) -> WidgetHistorySummary {
        WidgetHistorySummary(
            historyStartEpoch: summary.historyStartEpoch,
            days: summary.days.filter { $0.dayStartEpoch >= sinceEpoch }
        )
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
