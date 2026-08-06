import AgentMeterCore

public enum WidgetFreshnessState: Equatable, Sendable {
    case fresh
    case stale
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
    public let rings: [WidgetRingPresentation]

    public init(id: String, name: String, status: String, rings: [WidgetRingPresentation]) {
        self.id = id
        self.name = name
        self.status = status
        self.rings = rings
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

    public init(
        configuration: WidgetRenderConfiguration,
        family: WidgetFamily,
        providers: [WidgetProviderPresentation],
        modules: Set<WidgetModule>,
        history: WidgetHistoryProjection?,
        freshness: WidgetFreshnessState,
        overflowCount: Int
    ) {
        self.configuration = configuration
        self.family = family
        self.providers = providers
        self.modules = modules
        self.history = history
        self.freshness = freshness
        self.overflowCount = overflowCount
    }
}

public enum WidgetPresentationResolver {
    public static let unavailableHistoryMessage = "History unavailable for this window"

    public static func resolve(
        configuration: WidgetRenderConfiguration,
        snapshot: WidgetSnapshot,
        family: WidgetFamily,
        nowEpoch: Int,
        endingAtDayEpoch: Int? = nil
    ) -> WidgetPresentation {
        let candidates = selectedProviders(configuration: configuration, snapshot: snapshot)
        let maximum = configuration.kind == .focus ? 1 : family.maximumDashboardProviders
        let resolvedSnapshots = Array(candidates.prefix(maximum))
        let overflowCount = max(0, candidates.count - resolvedSnapshots.count)
        let modules = resolvedModules(requested: configuration.modules, family: family)
        let providers = resolvedSnapshots.map {
            resolveProvider($0, configuration: configuration, nowEpoch: nowEpoch)
        }
        let history = resolveHistory(
            configuration: configuration,
            providers: resolvedSnapshots,
            modules: modules,
            endingAtDayEpoch: endingAtDayEpoch ?? dayEpoch(containing: nowEpoch)
        )

        return WidgetPresentation(
            configuration: configuration,
            family: family,
            providers: providers,
            modules: modules,
            history: history,
            freshness: nowEpoch >= staleEpoch(for: snapshot) ? .stale : .fresh,
            overflowCount: overflowCount
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
    ) -> [WidgetProviderSnapshot] {
        let byID = Dictionary(
            snapshot.providers.reversed().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let requested = configuration.providerIDs.compactMap { id -> WidgetProviderSnapshot? in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }

        switch configuration.kind {
        case .dashboard:
            return configuration.providerIDs.isEmpty ? snapshot.providers : requested
        case .focus:
            if let focusProviderID = configuration.focusProviderID, let provider = byID[focusProviderID] {
                return [provider]
            }
            return Array((requested.isEmpty ? snapshot.providers : requested).prefix(1))
        }
    }

    private static func resolvedModules(
        requested: Set<WidgetModule>,
        family: WidgetFamily
    ) -> Set<WidgetModule> {
        var result = requested.union([.usage, .primaryReset])
        let capacity: Int
        switch family {
        case .small: capacity = 2
        case .medium: capacity = 4
        case .large, .extraLarge: capacity = WidgetModule.allCases.count
        }

        for module in [WidgetModule.history, .status, .freshness] where result.count > capacity {
            result.remove(module)
        }
        return result
    }

    private static func resolveProvider(
        _ provider: WidgetProviderSnapshot,
        configuration: WidgetRenderConfiguration,
        nowEpoch: Int
    ) -> WidgetProviderPresentation {
        let selection = WidgetWindowSelector.select(
            from: provider.windows.map {
                ProviderWindow(
                    kind: $0.kind,
                    label: $0.label,
                    usedPercent: $0.usedPercent,
                    resetAtEpoch: $0.resetAtEpoch
                )
            },
            focusOuterKind: configuration.kind == .focus ? configuration.outerWindowKind : nil,
            focusInnerKind: configuration.kind == .focus ? configuration.innerWindowKind : nil
        )
        let rings = [selection.outer, selection.inner].compactMap { window in
            window.map {
                ring(window: $0, mode: configuration.percentageMode, nowEpoch: nowEpoch)
            }
        }
        return WidgetProviderPresentation(
            id: provider.id,
            name: provider.name,
            status: provider.status,
            rings: rings
        )
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
        endingAtDayEpoch: Int
    ) -> WidgetHistoryProjection? {
        guard modules.contains(.history) else { return nil }

        let focusWindowKind = configuration.kind == .focus
            ? configuration.outerWindowKind
            : nil
        if let provider = providers.first,
           let focusWindowKind,
           provider.history.contains(where: { $0.windowKind == focusWindowKind }) == false {
            return WidgetHistoryProjection(cells: [], availabilityMessage: unavailableHistoryMessage)
        }
        return WidgetHistoryProjection(
            cells: WidgetHistoryProjection.heatMap(
                providers: providers,
                range: configuration.historyPeriod,
                scope: configuration.heatMapScope,
                selectedProviderID: configuration.focusProviderID ?? providers.first?.id,
                windowKind: focusWindowKind,
                endingAtDayEpoch: endingAtDayEpoch
            )
        )
    }

    private static func dayEpoch(containing epoch: Int) -> Int {
        epoch - epoch % 86_400
    }
}
