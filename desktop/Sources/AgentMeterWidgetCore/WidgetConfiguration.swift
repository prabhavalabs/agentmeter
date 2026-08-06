public enum WidgetKind: String, Codable, Equatable, Sendable, CaseIterable {
    case dashboard
    case focus
}

public enum WidgetFamily: String, Codable, Equatable, Sendable, CaseIterable {
    case small
    case medium
    case large
    case extraLarge

    public var maximumDashboardProviders: Int {
        switch self {
        case .small: 2
        case .medium: 4
        case .large: 5
        case .extraLarge: 8
        }
    }
}

public enum WidgetPercentageMode: String, Codable, Equatable, Sendable, CaseIterable {
    case used
    case remaining
}

public enum WidgetModule: String, Codable, Equatable, Sendable, CaseIterable {
    case usage
    case primaryReset
    case history
    case status
    case freshness
}

public enum WidgetHistoryStyle: String, Codable, Equatable, Sendable, CaseIterable {
    case heatMap
    case bars
}

public enum WidgetHistoryPeriod: String, Codable, Equatable, Sendable, CaseIterable {
    case days7
    case days30

    public var dayCount: Int {
        switch self {
        case .days7: 7
        case .days30: 30
        }
    }
}

public enum WidgetHeatMapScope: String, Codable, Equatable, Sendable, CaseIterable {
    case singleProvider
    case combined
}

public enum WidgetLayoutPreset: String, Codable, Equatable, Sendable, CaseIterable {
    case automatic
    case compact
    case expanded
}

public enum WidgetDensity: String, Codable, Equatable, Sendable, CaseIterable {
    case compact
    case comfortable
}

public enum WidgetTheme: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

public enum WidgetTapDestination: String, Codable, Equatable, Sendable, CaseIterable {
    case dashboard
    case provider
    case settings
}

public struct WidgetRenderConfiguration: Equatable, Sendable {
    public let kind: WidgetKind
    public let providerIDs: [String]
    public let focusProviderID: String?
    public let outerWindowKind: String?
    public let innerWindowKind: String?
    public let percentageMode: WidgetPercentageMode
    public let modules: Set<WidgetModule>
    public let historyStyle: WidgetHistoryStyle
    public let historyPeriod: WidgetHistoryPeriod
    public let heatMapScope: WidgetHeatMapScope
    public let layout: WidgetLayoutPreset
    public let density: WidgetDensity
    public let theme: WidgetTheme
    public let tapDestination: WidgetTapDestination

    public init(
        kind: WidgetKind,
        providerIDs: [String],
        focusProviderID: String?,
        outerWindowKind: String?,
        innerWindowKind: String?,
        percentageMode: WidgetPercentageMode,
        modules: Set<WidgetModule>,
        historyStyle: WidgetHistoryStyle,
        historyPeriod: WidgetHistoryPeriod,
        heatMapScope: WidgetHeatMapScope,
        layout: WidgetLayoutPreset,
        density: WidgetDensity,
        theme: WidgetTheme,
        tapDestination: WidgetTapDestination
    ) {
        self.kind = kind
        self.providerIDs = providerIDs
        self.focusProviderID = focusProviderID
        self.outerWindowKind = outerWindowKind
        self.innerWindowKind = innerWindowKind
        self.percentageMode = percentageMode
        self.modules = modules
        self.historyStyle = historyStyle
        self.historyPeriod = historyPeriod
        self.heatMapScope = heatMapScope
        self.layout = layout
        self.density = density
        self.theme = theme
        self.tapDestination = tapDestination
    }
}
