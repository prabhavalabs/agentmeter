import SwiftUI
import WidgetKit

@main
struct AgentMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentMeterDashboardWidget()
        AgentMeterFocusWidget()
    }
}

struct AgentMeterDashboardWidget: Widget {
    let kind = "com.prabhavalabs.agentmeter.dashboard"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DashboardWidgetIntent.self,
            provider: DashboardTimelineProvider()
        ) { entry in
            DashboardTimelineEntryView(entry: entry)
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
            provider: FocusTimelineProvider()
        ) { entry in
            FocusTimelineEntryView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Focus")
        .description("Focused agent allowance limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
