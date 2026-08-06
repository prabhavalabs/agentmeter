import AgentMeterWidgetCore
import SwiftUI
import WidgetKit

enum FictionalDashboardPresentations {
    static func usedHeat(
        family: AgentMeterWidgetCore.WidgetFamily,
        theme: IntentThemeOption = .providerTinted
    ) -> WidgetPresentation {
        let intent = baseIntent()
        intent.historyStyle = .heatMap
        intent.historyRange = .days30
        intent.heatScope = .combined
        intent.percentage = .used
        intent.theme = theme
        return FictionalDashboardPresentationSource.presentation(for: intent, family: family)
    }

    static func remainingTrend(
        family: AgentMeterWidgetCore.WidgetFamily,
        theme: IntentThemeOption = .midnight
    ) -> WidgetPresentation {
        let intent = baseIntent()
        intent.providers = [ProviderEntity(id: "gemini", name: "Gemini")]
        intent.historyStyle = .trend
        intent.historyRange = .days7
        intent.trendWindow = .inner
        intent.percentage = .remaining
        intent.theme = theme
        return FictionalDashboardPresentationSource.presentation(for: intent, family: family)
    }

    static func unknown(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
        let intent = baseIntent()
        intent.providers = [ProviderEntity(id: "unknown provider", name: "Unknown Provider")]
        intent.theme = .midnight
        return FictionalDashboardPresentationSource.presentation(for: intent, family: family)
    }

    static func unavailableHistory(family: AgentMeterWidgetCore.WidgetFamily) -> WidgetPresentation {
        let intent = baseIntent()
        intent.providers = [ProviderEntity(id: "codex", name: "Codex")]
        intent.historyStyle = .trend
        intent.trendWindow = .focus
        intent.theme = .light
        return FictionalDashboardPresentationSource.presentation(for: intent, family: family)
    }

    private static func baseIntent() -> DashboardWidgetIntent {
        let intent = DashboardWidgetIntent()
        intent.providers = FictionalDashboardPresentationSource.providerEntities
        intent.layout = .expanded
        intent.density = .compact
        intent.showResetCountdown = true
        intent.showAbsoluteResetDate = true
        intent.showStatus = true
        intent.showFreshness = true
        return intent
    }
}

#Preview("Overflow · Light · Small", as: .systemSmall) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.usedHeat(family: .small, theme: .light)
    )
}

#Preview("Remaining · Midnight · Medium", as: .systemMedium) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.remainingTrend(family: .medium)
    )
}

#Preview("Heat · Provider Tinted · Large", as: .systemLarge) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.usedHeat(family: .large)
    )
}

#Preview("Trend · Remaining · Large", as: .systemLarge) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.remainingTrend(family: .large)
    )
}

#Preview("Eight Providers · Light · Extra Large", as: .systemExtraLarge) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.usedHeat(family: .extraLarge, theme: .light)
    )
}

#Preview("Trend · Midnight · Extra Large", as: .systemExtraLarge) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.remainingTrend(family: .extraLarge)
    )
}

#Preview("Unknown Selection · Large", as: .systemLarge) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.unknown(family: .large)
    )
}

#Preview("Unavailable History · Large", as: .systemLarge) {
    AgentMeterDashboardWidget()
} timeline: {
    FictionalUsageEntry(
        date: Date(timeIntervalSince1970: TimeInterval(FictionalDashboardPresentationSource.endingDayEpoch)),
        dashboardPresentation: FictionalDashboardPresentations.unavailableHistory(family: .large)
    )
}
