import AppIntents
import AgentMeterWidgetCore
import SwiftUI
import WidgetKit

struct FictionalUsageEntry: TimelineEntry {
    let date: Date
    let dashboardPresentation: WidgetPresentation?
    let focusPresentation: WidgetPresentation?

    init(
        date: Date,
        dashboardPresentation: WidgetPresentation? = nil,
        focusPresentation: WidgetPresentation? = nil
    ) {
        self.date = date
        self.dashboardPresentation = dashboardPresentation
        self.focusPresentation = focusPresentation
    }
}

private struct FictionalDashboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FictionalUsageEntry {
        entry(configuration: DashboardWidgetIntent(), family: context.family)
    }

    func snapshot(for configuration: DashboardWidgetIntent, in context: Context) async -> FictionalUsageEntry {
        entry(configuration: configuration, family: context.family)
    }

    func timeline(for configuration: DashboardWidgetIntent, in context: Context) async -> Timeline<FictionalUsageEntry> {
        Timeline(entries: [entry(configuration: configuration, family: context.family)], policy: .never)
    }

    private func entry(
        configuration: DashboardWidgetIntent,
        family: WidgetKit.WidgetFamily
    ) -> FictionalUsageEntry {
        FictionalUsageEntry(
            date: Date(),
            dashboardPresentation: FictionalDashboardPresentationSource.presentation(
                for: configuration,
                family: family.presentationFamily
            )
        )
    }
}

private struct FictionalFocusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FictionalUsageEntry {
        entry(configuration: FocusWidgetIntent(), family: context.family)
    }

    func snapshot(for configuration: FocusWidgetIntent, in context: Context) async -> FictionalUsageEntry {
        entry(configuration: configuration, family: context.family)
    }

    func timeline(for configuration: FocusWidgetIntent, in context: Context) async -> Timeline<FictionalUsageEntry> {
        Timeline(entries: [entry(configuration: configuration, family: context.family)], policy: .never)
    }

    private func entry(
        configuration: FocusWidgetIntent,
        family: WidgetKit.WidgetFamily
    ) -> FictionalUsageEntry {
        FictionalUsageEntry(
            date: Date(),
            focusPresentation: FictionalFocusPresentationSource.presentation(
                for: configuration,
                family: family.presentationFamily
            )
        )
    }
}

private struct DashboardContentView: View {
    let entry: FictionalUsageEntry

    var body: some View {
        if let presentation = entry.dashboardPresentation {
            DashboardWidgetView(presentation: presentation)
        } else {
            WidgetStateView(title: "Fictional preview unavailable", systemImage: "sparkles")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

private struct FocusContentView: View {
    let entry: FictionalUsageEntry

    var body: some View {
        if let presentation = entry.focusPresentation {
            FocusWidgetView(presentation: presentation)
        } else {
            WidgetStateView(title: "Fictional preview unavailable", systemImage: "sparkles")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct AgentMeterDashboardWidget: Widget {
    let kind = "com.prabhavalabs.agentmeter.dashboard"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DashboardWidgetIntent.self,
            provider: FictionalDashboardProvider()
        ) { entry in
            DashboardContentView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Dashboard")
        .description("Overall agent allowance usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct AgentMeterFocusWidget: Widget {
    let kind = "com.prabhavalabs.agentmeter.focus"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FocusWidgetIntent.self,
            provider: FictionalFocusProvider()
        ) { entry in
            FocusContentView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Focus")
        .description("Focused agent allowance limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

private extension WidgetKit.WidgetFamily {
    var presentationFamily: AgentMeterWidgetCore.WidgetFamily {
        switch self {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        case .systemExtraLarge: .extraLarge
        @unknown default: .small
        }
    }
}
