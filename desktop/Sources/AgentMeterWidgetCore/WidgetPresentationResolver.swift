import AgentMeterCore
import Foundation

public enum WidgetFreshnessState: Equatable, Sendable {
    case fresh
    case stale
}

public enum WidgetProviderAvailability: Equatable, Sendable {
    case available
    case missing
}

public enum WidgetProviderHealthState: Equatable, Sendable {
    case healthy
    case stale
    case error
    case unavailable
    case attention
}

public enum WidgetResetState: Equatable, Sendable {
    case unavailable
    case scheduled(epoch: Int)
    case pending
}

public struct WidgetRingPresentation: Equatable, Sendable {
    public let windowKind: String
    public let label: String
    public let usedPercent: Int?
    public let displayedPercent: Int?
    public let resetState: WidgetResetState

    public var resetText: String? {
        switch resetState {
        case .unavailable: nil
        case .scheduled: "Reset scheduled"
        case .pending: "Refresh pending"
        }
    }

    public init(
        windowKind: String,
        label: String,
        usedPercent: Int?,
        displayedPercent: Int?,
        resetState: WidgetResetState
    ) {
        self.windowKind = windowKind
        self.label = label
        self.usedPercent = usedPercent
        self.displayedPercent = displayedPercent
        self.resetState = resetState
    }
}

public struct WidgetProviderPresentation: Equatable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let availability: WidgetProviderAvailability
    public let healthState: WidgetProviderHealthState
    public let rings: [WidgetRingPresentation]
    public let additionalWindows: [WidgetRingPresentation]

    public init(
        id: String,
        name: String,
        status: String,
        availability: WidgetProviderAvailability = .available,
        healthState: WidgetProviderHealthState = .healthy,
        rings: [WidgetRingPresentation],
        additionalWindows: [WidgetRingPresentation] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.availability = availability
        self.healthState = healthState
        self.rings = rings
        self.additionalWindows = additionalWindows
    }
}

public struct WidgetPresentation: Equatable, Sendable {
    public let configuration: WidgetRenderConfiguration
    public let family: WidgetFamily
    public let providers: [WidgetProviderPresentation]
    public let modules: Set<WidgetModule>
    public let history: WidgetHistoryProjection?
    public let freshness: WidgetFreshnessState
    public let overflowCount: Int
    public let hasAvailableProviderSelection: Bool

    public init(
        configuration: WidgetRenderConfiguration,
        family: WidgetFamily,
        providers: [WidgetProviderPresentation],
        modules: Set<WidgetModule>,
        history: WidgetHistoryProjection?,
        freshness: WidgetFreshnessState,
        overflowCount: Int,
        hasAvailableProviderSelection: Bool? = nil
    ) {
        self.configuration = configuration
        self.family = family
        self.providers = providers
        self.modules = modules
        self.history = history
        self.freshness = freshness
        self.overflowCount = overflowCount
        self.hasAvailableProviderSelection = hasAvailableProviderSelection
            ?? providers.contains { $0.availability == .available }
    }
}

public enum WidgetPresentationResolver {
    public static let unavailableHistoryMessage = "History unavailable for this window"

    public static func resolve(
        configuration: WidgetRenderConfiguration,
        snapshot: WidgetSnapshot,
        family: WidgetFamily,
        nowEpoch: Int,
        endingAtDayEpoch: Int? = nil,
        calendar: Calendar = .current
    ) -> WidgetPresentation {
        let candidates = selectedProviders(configuration: configuration, snapshot: snapshot)
        let maximum = configuration.kind == .focus ? 1 : family.maximumDashboardProviders
        let renderedCandidates = Array(candidates.prefix(maximum))
        let resolvedSnapshots = renderedCandidates.compactMap(\.snapshot)
        let overflowCount = max(0, candidates.count - renderedCandidates.count)
        let modules = resolvedModules(
            requested: configuration.modules,
            kind: configuration.kind,
            family: family
        )
        let providers = renderedCandidates.map { candidate in
            switch candidate {
            case let .available(provider):
                resolveProvider(provider, configuration: configuration, nowEpoch: nowEpoch)
            case let .missing(slot):
                unavailableProvider(slot: slot)
            }
        }
        let history = resolveHistory(
            configuration: configuration,
            providers: resolvedSnapshots,
            modules: modules,
            endingAtDayEpoch: endingAtDayEpoch ?? dayEpoch(containing: nowEpoch, calendar: calendar),
            calendar: calendar
        )

        return WidgetPresentation(
            configuration: configuration,
            family: family,
            providers: providers,
            modules: modules,
            history: history,
            freshness: nowEpoch >= staleEpoch(for: snapshot) ? .stale : .fresh,
            overflowCount: overflowCount,
            hasAvailableProviderSelection: candidates.contains { $0.snapshot != nil }
        )
    }

    static func staleThreshold(pollIntervalSeconds: Int) -> Int {
        guard pollIntervalSeconds > 0 else { return 900 }
        let (doubled, overflow) = pollIntervalSeconds.multipliedReportingOverflow(by: 2)
        return overflow ? Int.max : max(doubled, 900)
    }

    static func staleEpoch(for snapshot: WidgetSnapshot) -> Int {
        let threshold = staleThreshold(pollIntervalSeconds: snapshot.pollIntervalSeconds)
        let (epoch, overflow) = snapshot.generatedAtEpoch.addingReportingOverflow(threshold)
        return overflow ? Int.max : epoch
    }

    private static func selectedProviders(
        configuration: WidgetRenderConfiguration,
        snapshot: WidgetSnapshot
    ) -> [SelectedProvider] {
        let byID = Dictionary(
            snapshot.providers.reversed().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let requested = configuration.providerIDs.enumerated().compactMap { slot, id -> SelectedProvider? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id].map(SelectedProvider.available) ?? .missing(slot: slot)
        }

        switch configuration.kind {
        case .dashboard:
            return configuration.providerIDs.isEmpty
                ? snapshot.providers.map(SelectedProvider.available)
                : requested
        case .focus:
            if let focusProviderID = configuration.focusProviderID, let provider = byID[focusProviderID] {
                return [.available(provider)]
            }
            let availableRequested = requested.compactMap(\.snapshot).map(SelectedProvider.available)
            return Array((availableRequested.isEmpty
                ? snapshot.providers.map(SelectedProvider.available)
                : availableRequested).prefix(1))
        }
    }

    private static func resolvedModules(
        requested: Set<WidgetModule>,
        kind: WidgetKind,
        family: WidgetFamily
    ) -> Set<WidgetModule> {
        var result = requested.union([.usage, .primaryReset])
        if family == .small {
            result.remove(.history)
            result.remove(.status)
            result.remove(.freshness)
        } else if family == .medium {
            switch kind {
            case .dashboard:
                result.remove(.history)
            case .focus:
                result.remove(.status)
                result.remove(.freshness)
            }
        }
        return result
    }

    private static func resolveProvider(
        _ provider: WidgetProviderSnapshot,
        configuration: WidgetRenderConfiguration,
        nowEpoch: Int
    ) -> WidgetProviderPresentation {
        let selection = WidgetWindowSelector.select(
            from: providerWindows(provider),
            focusOuterKind: configuration.kind == .focus ? configuration.outerWindowKind : nil,
            focusInnerKind: configuration.kind == .focus ? configuration.innerWindowKind : nil
        )
        let rings = [selection.outer, selection.inner].compactMap { window in
            window.map {
                ring(window: $0, mode: configuration.percentageMode, nowEpoch: nowEpoch)
            }
        }
        let additionalWindows = selection.additional.map {
            ring(window: $0, mode: configuration.percentageMode, nowEpoch: nowEpoch)
        }
        return WidgetProviderPresentation(
            id: provider.id,
            name: provider.name,
            status: provider.status,
            healthState: healthState(for: provider.status),
            rings: rings,
            additionalWindows: additionalWindows
        )
    }

    private static func unavailableProvider(slot: Int) -> WidgetProviderPresentation {
        WidgetProviderPresentation(
            id: "unavailable-provider-slot-\(slot)",
            name: "Agent unavailable",
            status: "Agent unavailable",
            availability: .missing,
            healthState: .unavailable,
            rings: []
        )
    }

    private static func healthState(for status: String) -> WidgetProviderHealthState {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ok", "ready", "allowance available", "fictional allowance data":
            return .healthy
        case "stale", "awaiting refresh", "waiting for refresh":
            return .stale
        default:
            if normalized.hasPrefix("error") { return .error }
            if normalized.contains("unavailable") { return .unavailable }
            return .attention
        }
    }

    private static func ring(
        window: ProviderWindow,
        mode: WidgetPercentageMode,
        nowEpoch: Int
    ) -> WidgetRingPresentation {
        let resetState: WidgetResetState
        if let reset = window.resetAtEpoch {
            resetState = reset <= nowEpoch ? .pending : .scheduled(epoch: reset)
        } else {
            resetState = .unavailable
        }
        let displayed = window.usedPercent.map { mode == .used ? $0 : 100 - $0 }
        return WidgetRingPresentation(
            windowKind: window.kind,
            label: window.label,
            usedPercent: window.usedPercent,
            displayedPercent: displayed,
            resetState: resetState
        )
    }

    private static func resolveHistory(
        configuration: WidgetRenderConfiguration,
        providers: [WidgetProviderSnapshot],
        modules: Set<WidgetModule>,
        endingAtDayEpoch: Int,
        calendar: Calendar
    ) -> WidgetHistoryProjection? {
        guard modules.contains(.history), configuration.historyStyle != .none else { return nil }

        let firstProvider = providers.first
        let selectedWindow = firstProvider.flatMap {
            historyWindow(provider: $0, configuration: configuration)
        }
        if let firstProvider, let selectedWindow,
           WidgetWindowSelector.historyEnabledKinds(from: providerWindows(firstProvider))
            .contains(selectedWindow.kind) == false {
            return WidgetHistoryProjection(
                windowKind: selectedWindow.kind,
                windowLabel: selectedWindow.label,
                availabilityMessage: unavailableHistoryMessage
            )
        }

        switch configuration.historyStyle {
        case .none:
            return nil
        case .trend:
            guard let firstProvider, let selectedWindow else {
                return WidgetHistoryProjection(availabilityMessage: unavailableHistoryMessage)
            }
            guard let trendPoints = WidgetHistoryProjection.trend(
                provider: firstProvider,
                range: configuration.historyPeriod,
                windowKind: selectedWindow.kind,
                endingAtDayEpoch: endingAtDayEpoch,
                calendar: calendar
            ) else {
                return WidgetHistoryProjection(
                    windowKind: selectedWindow.kind,
                    windowLabel: selectedWindow.label,
                    availabilityMessage: unavailableHistoryMessage
                )
            }
            return WidgetHistoryProjection(
                trendPoints: trendPoints,
                windowKind: selectedWindow.kind,
                windowLabel: selectedWindow.label
            )
        case .heatMap, .bars:
            guard configuration.historyPeriod != .currentCycle else {
                return WidgetHistoryProjection(availabilityMessage: unavailableHistoryMessage)
            }
            let focusWindowKind = configuration.kind == .focus ? selectedWindow?.kind : nil
            return WidgetHistoryProjection(
                cells: WidgetHistoryProjection.heatMap(
                    providers: providers,
                    range: configuration.historyPeriod,
                    scope: configuration.heatMapScope,
                    selectedProviderID: configuration.focusProviderID ?? firstProvider?.id,
                    windowKind: focusWindowKind,
                    endingAtDayEpoch: endingAtDayEpoch,
                    calendar: calendar
                ),
                windowKind: focusWindowKind,
                windowLabel: configuration.kind == .focus ? selectedWindow?.label : nil
            )
        }
    }

    private static func historyWindow(
        provider: WidgetProviderSnapshot,
        configuration: WidgetRenderConfiguration
    ) -> ProviderWindow? {
        let windows = providerWindows(provider)
        let selection = WidgetWindowSelector.select(
            from: windows,
            focusOuterKind: configuration.kind == .focus ? configuration.outerWindowKind : nil,
            focusInnerKind: configuration.kind == .focus ? configuration.innerWindowKind : nil
        )
        guard configuration.historyStyle == .trend else { return selection.outer }

        switch configuration.trendWindow {
        case .outer:
            return selection.outer
        case .inner:
            return selection.inner
        case .focus:
            guard let kind = configuration.trendFocusWindowKind else { return nil }
            return windows.first { $0.kind == kind }
        }
    }

    private static func dayEpoch(containing epoch: Int, calendar: Calendar) -> Int {
        Int(calendar.startOfDay(
            for: Date(timeIntervalSince1970: TimeInterval(epoch))
        ).timeIntervalSince1970)
    }

    private static func providerWindows(_ provider: WidgetProviderSnapshot) -> [ProviderWindow] {
        provider.windows.map {
            ProviderWindow(
                kind: $0.kind,
                label: $0.label,
                usedPercent: $0.usedPercent,
                resetAtEpoch: $0.resetAtEpoch
            )
        }
    }

    private enum SelectedProvider {
        case available(WidgetProviderSnapshot)
        case missing(slot: Int)

        var snapshot: WidgetProviderSnapshot? {
            guard case let .available(snapshot) = self else { return nil }
            return snapshot
        }
    }
}
