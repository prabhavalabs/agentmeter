import AgentMeterWidgetCore

enum IntentConfigurationAdapter {
    static func dashboard(_ intent: DashboardWidgetIntent) -> WidgetRenderConfiguration {
        configuration(
            kind: .dashboard,
            providerIDs: intent.providers?.map(\.id) ?? [],
            focusProviderID: nil,
            outerWindowKind: nil,
            innerWindowKind: nil,
            percentage: intent.percentage,
            historyStyle: intent.historyStyle,
            historyRange: intent.historyRange,
            heatScope: intent.heatScope,
            trendWindow: intent.trendWindow,
            layout: intent.layout,
            density: intent.density,
            theme: intent.theme,
            tapDestination: intent.tapDestination,
            showResetCountdown: intent.showResetCountdown,
            showAbsoluteResetDate: intent.showAbsoluteResetDate,
            showStatus: intent.showStatus,
            showFreshness: intent.showFreshness
        )
    }

    static func focus(_ intent: FocusWidgetIntent) -> WidgetRenderConfiguration {
        let providerID = intent.provider?.id
        return configuration(
            kind: .focus,
            providerIDs: providerID.map { [$0] } ?? [],
            focusProviderID: providerID,
            outerWindowKind: matchingWindowKind(intent.outerWindow, providerID: providerID),
            innerWindowKind: matchingWindowKind(intent.innerWindow, providerID: providerID),
            percentage: intent.percentage,
            historyStyle: intent.historyStyle,
            historyRange: intent.historyRange,
            heatScope: intent.heatScope,
            trendWindow: intent.trendWindow,
            layout: intent.layout,
            density: intent.density,
            theme: intent.theme,
            tapDestination: intent.tapDestination,
            showResetCountdown: intent.showResetCountdown,
            showAbsoluteResetDate: intent.showAbsoluteResetDate,
            showStatus: intent.showStatus,
            showFreshness: intent.showFreshness
        )
    }

    private static func matchingWindowKind(
        _ window: WindowEntity?,
        providerID: String?
    ) -> String? {
        guard let providerID, window?.providerID == providerID else { return nil }
        return window?.windowKind
    }

    private static func configuration(
        kind: WidgetKind,
        providerIDs: [String],
        focusProviderID: String?,
        outerWindowKind: String?,
        innerWindowKind: String?,
        percentage: IntentPercentageOption,
        historyStyle: IntentHistoryStyleOption,
        historyRange: IntentHistoryRangeOption,
        heatScope: IntentHeatScopeOption,
        trendWindow: IntentTrendWindowOption,
        layout: IntentLayoutOption,
        density: IntentDensityOption,
        theme: IntentThemeOption,
        tapDestination: IntentTapDestinationOption,
        showResetCountdown: Bool,
        showAbsoluteResetDate: Bool,
        showStatus: Bool,
        showFreshness: Bool
    ) -> WidgetRenderConfiguration {
        var modules: Set<WidgetModule> = [.usage, .primaryReset]
        if historyStyle != .none { modules.insert(.history) }
        if showStatus { modules.insert(.status) }
        if showFreshness { modules.insert(.freshness) }

        return WidgetRenderConfiguration(
            kind: kind,
            providerIDs: providerIDs,
            focusProviderID: focusProviderID,
            outerWindowKind: outerWindowKind,
            innerWindowKind: innerWindowKind,
            percentageMode: percentage.renderValue,
            modules: modules,
            historyStyle: historyStyle.renderValue,
            historyPeriod: historyRange.renderValue,
            heatMapScope: heatScope.renderValue,
            trendWindow: trendWindow.renderValue,
            layout: layout.renderValue,
            density: density.renderValue,
            theme: theme.renderValue,
            tapDestination: tapDestination.renderValue,
            showsResetCountdown: showResetCountdown,
            showsAbsoluteResetDate: showAbsoluteResetDate
        )
    }
}

private extension IntentPercentageOption {
    var renderValue: WidgetPercentageMode {
        switch self { case .used: .used; case .remaining: .remaining }
    }
}

private extension IntentHistoryStyleOption {
    var renderValue: WidgetHistoryStyle {
        switch self { case .heatMap: .heatMap; case .trend: .trend; case .none: .none }
    }
}

private extension IntentHistoryRangeOption {
    var renderValue: WidgetHistoryPeriod {
        switch self { case .days7: .days7; case .days30: .days30 }
    }
}

private extension IntentHeatScopeOption {
    var renderValue: WidgetHeatMapScope {
        switch self { case .combined: .combined; case .singleProvider: .singleProvider }
    }
}

private extension IntentTrendWindowOption {
    var renderValue: WidgetTrendWindow {
        switch self { case .outer: .outer; case .inner: .inner; case .focus: .focus }
    }
}

private extension IntentLayoutOption {
    var renderValue: WidgetLayoutPreset {
        switch self {
        case .automatic: .automatic
        case .usageAndRings: .usageAndRings
        case .compact: .compact
        case .expanded: .expanded
        }
    }
}

private extension IntentDensityOption {
    var renderValue: WidgetDensity {
        switch self { case .compact: .compact; case .comfortable: .comfortable }
    }
}

private extension IntentThemeOption {
    var renderValue: WidgetTheme {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        case .midnight: .midnight
        }
    }
}

private extension IntentTapDestinationOption {
    var renderValue: WidgetTapDestination {
        switch self {
        case .overview: .dashboard
        case .providerDetail: .provider
        case .agents: .agents
        case .settings: .settings
        }
    }
}
