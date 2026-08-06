import SwiftUI
import WidgetKit

private struct FictionalUsageEntry: TimelineEntry {
    let date: Date
}

private struct FictionalUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> FictionalUsageEntry {
        FictionalUsageEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (FictionalUsageEntry) -> Void
    ) {
        completion(FictionalUsageEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<FictionalUsageEntry>) -> Void
    ) {
        completion(Timeline(entries: [FictionalUsageEntry(date: Date())], policy: .never))
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
        StaticConfiguration(kind: kind, provider: FictionalUsageProvider()) { entry in
            DashboardPlaceholderView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Dashboard")
        .description("A fictional preview of overall coding-agent usage.")
    }
}

struct AgentMeterFocusWidget: Widget {
    let kind = "com.prabhavalabs.agentmeter.focus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FictionalUsageProvider()) { entry in
            FocusPlaceholderView(entry: entry)
        }
        .configurationDisplayName("AgentMeter Focus")
        .description("A fictional preview of the current coding session.")
    }
}
