import AppIntents

enum IntentPercentageOption: String, AppEnum {
    case used
    case remaining

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Percentage")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .used: "Used",
        .remaining: "Remaining",
    ]
}

enum IntentHistoryStyleOption: String, AppEnum {
    case heatMap
    case trend
    case none

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "History Style")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .heatMap: "Heat Map",
        .trend: "Trend",
        .none: "None",
    ]
}

enum IntentHistoryRangeOption: String, AppEnum {
    case days7
    case days30
    case currentCycle

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "History Range")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .days7: "7 Days",
        .days30: "30 Days",
        .currentCycle: "Current Cycle",
    ]
}

enum IntentHeatScopeOption: String, AppEnum {
    case combined
    case singleProvider

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Heat Map Scope")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .combined: "Combined Providers",
        .singleProvider: "Single Provider",
    ]
}

enum IntentTrendWindowOption: String, AppEnum {
    case outer
    case inner
    case focus

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trend Window")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .outer: "Outer Ring",
        .inner: "Inner Ring",
        .focus: "Specific Focus Window",
    ]
}

enum IntentLayoutOption: String, AppEnum {
    case automatic
    case usageAndRings
    case compact
    case expanded

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Layout")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic",
        .usageAndRings: "Usage and Rings",
        .compact: "Compact",
        .expanded: "Expanded",
    ]
}

enum IntentDensityOption: String, AppEnum {
    case compact
    case comfortable

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Density")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .compact: "Compact",
        .comfortable: "Comfortable",
    ]
}

enum IntentThemeOption: String, AppEnum {
    case system
    case light
    case dark
    case midnight
    case neutral
    case providerTinted

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Theme")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .system: "System",
        .light: "Light",
        .dark: "Dark",
        .midnight: "Midnight",
        .neutral: "Neutral",
        .providerTinted: "Provider Tinted",
    ]
}

enum IntentTapDestinationOption: String, AppEnum {
    case overview
    case providerDetail
    case agents

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tap Destination")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .overview: "Overview",
        .providerDetail: "Provider Detail",
        .agents: "Agents",
    ]
}

struct DashboardWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Dashboard"
    static let description = IntentDescription("Choose the providers and presentation shown in the AgentMeter dashboard widget.")

    @Parameter(title: "Providers") var providers: [ProviderEntity]?
    @Parameter(title: "Percentage", default: .used) var percentage: IntentPercentageOption
    @Parameter(title: "History", default: .heatMap) var historyStyle: IntentHistoryStyleOption
    @Parameter(title: "History Range", default: .days30) var historyRange: IntentHistoryRangeOption
    @Parameter(title: "Heat Map Scope", default: .combined) var heatScope: IntentHeatScopeOption
    @Parameter(title: "Trend Window", default: .outer) var trendWindow: IntentTrendWindowOption
    @Parameter(title: "Layout", default: .usageAndRings) var layout: IntentLayoutOption
    @Parameter(title: "Density", default: .comfortable) var density: IntentDensityOption
    @Parameter(title: "Theme", default: .system) var theme: IntentThemeOption
    @Parameter(title: "Tap Opens", default: .overview) var tapDestination: IntentTapDestinationOption
    @Parameter(title: "Reset Countdown", default: true) var showResetCountdown: Bool
    @Parameter(title: "Absolute Reset Date", default: false) var showAbsoluteResetDate: Bool
    @Parameter(title: "Provider Status", default: false) var showStatus: Bool
    @Parameter(title: "Data Freshness", default: false) var showFreshness: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Dashboard: \(\.$percentage), \(\.$historyStyle), \(\.$layout)") {
            \.$providers
            \.$historyRange
            \.$heatScope
            \.$trendWindow
            \.$density
            \.$theme
            \.$tapDestination
            \.$showResetCountdown
            \.$showAbsoluteResetDate
            \.$showStatus
            \.$showFreshness
        }
    }

    init() {}
}

struct FocusWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Focus"
    static let description = IntentDescription("Choose one provider and its usage windows for the AgentMeter focus widget.")

    @Parameter(title: "Provider") var provider: ProviderEntity?
    @Parameter(title: "Outer Window", optionsProvider: WindowEntityQuery()) var outerWindow: WindowEntity?
    @Parameter(title: "Inner Window", optionsProvider: WindowEntityQuery()) var innerWindow: WindowEntity?
    @Parameter(title: "Specific Trend Window", optionsProvider: WindowEntityQuery())
    var specificTrendWindow: WindowEntity?
    @Parameter(title: "Percentage", default: .used) var percentage: IntentPercentageOption
    @Parameter(title: "History", default: .heatMap) var historyStyle: IntentHistoryStyleOption
    @Parameter(title: "History Range", default: .days30) var historyRange: IntentHistoryRangeOption
    @Parameter(title: "Heat Map Scope", default: .singleProvider) var heatScope: IntentHeatScopeOption
    @Parameter(title: "Trend Window", default: .outer) var trendWindow: IntentTrendWindowOption
    @Parameter(title: "Layout", default: .usageAndRings) var layout: IntentLayoutOption
    @Parameter(title: "Density", default: .comfortable) var density: IntentDensityOption
    @Parameter(title: "Theme", default: .system) var theme: IntentThemeOption
    @Parameter(title: "Tap Opens", default: .providerDetail) var tapDestination: IntentTapDestinationOption
    @Parameter(title: "Reset Countdown", default: true) var showResetCountdown: Bool
    @Parameter(title: "Absolute Reset Date", default: false) var showAbsoluteResetDate: Bool
    @Parameter(title: "Provider Status", default: false) var showStatus: Bool
    @Parameter(title: "Data Freshness", default: false) var showFreshness: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Focus: \(\.$provider), \(\.$percentage), \(\.$historyStyle)") {
            \.$outerWindow
            \.$innerWindow
            \.$specificTrendWindow
            \.$historyRange
            \.$heatScope
            \.$trendWindow
            \.$layout
            \.$density
            \.$theme
            \.$tapDestination
            \.$showResetCountdown
            \.$showAbsoluteResetDate
            \.$showStatus
            \.$showFreshness
        }
    }

    init() {}
}
