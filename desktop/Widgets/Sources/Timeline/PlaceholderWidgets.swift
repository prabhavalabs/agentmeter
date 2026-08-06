import AppIntents
import SwiftUI
import WidgetKit

private struct FictionalUsageEntry: TimelineEntry {
    let date: Date
}

private struct FictionalUsageProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FictionalUsageEntry {
        FictionalUsageEntry(date: Date())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> FictionalUsageEntry {
        FictionalUsageEntry(date: Date())
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<FictionalUsageEntry> {
        Timeline(entries: [FictionalUsageEntry(date: Date())], policy: .never)
    }
}

private struct DashboardPlaceholderView: View {
    var entry: FictionalUsageProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AgentMeter", systemImage: "gauge.with.dots.needle.67percent")
                .font(.headline)
            Text("Example usage")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("42%")
                .font(.system(.title, design: .rounded, weight: .semibold))
            ProgressView(value: 0.42)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct FocusPlaceholderView: View {
    var entry: FictionalUsageProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Focus", systemImage: "sparkles")
                .font(.headline)
            Text("Example session")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("18k tokens")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Fictional preview")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AgentMeterDashboardWidget: Widget {
    let kind = "com.prabhavalabs.agentmeter.dashboard"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DashboardWidgetIntent.self,
            provider: FictionalUsageProvider<DashboardWidgetIntent>()
        ) { entry in
            DashboardPlaceholderView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Dashboard")
        .description("A fictional preview of overall coding-agent usage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct AgentMeterFocusWidget: Widget {
    let kind = "com.prabhavalabs.agentmeter.focus"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: FocusWidgetIntent.self,
            provider: FictionalUsageProvider<FocusWidgetIntent>()
        ) { entry in
            FocusPlaceholderView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Focus")
        .description("A fictional preview of the current coding session.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
