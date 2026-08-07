import AgentMeterWidgetCore
import Foundation
import SwiftUI
import WidgetKit

struct DashboardTimelineProvider: AppIntentTimelineProvider {
    private let loader: WidgetSnapshotLoader
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        loader: WidgetSnapshotLoader = WidgetSnapshotLoader(),
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.loader = loader
        self.now = now
        self.calendar = calendar
    }

    func placeholder(in context: Context) -> WidgetTimelineEntry {
        placeholderEntry(family: context.family.presentationFamily)
    }

    func snapshot(
        for configuration: DashboardWidgetIntent,
        in context: Context
    ) async -> WidgetTimelineEntry {
        if context.isPreview {
            return placeholderEntry(for: configuration, family: context.family.presentationFamily)
        }
        return snapshotEntry(for: configuration, family: context.family.presentationFamily)
    }

    func timeline(
        for configuration: DashboardWidgetIntent,
        in context: Context
    ) async -> Timeline<WidgetTimelineEntry> {
        widgetTimeline(for: configuration, family: context.family.presentationFamily)
    }

    func placeholderEntry(
        for configuration: DashboardWidgetIntent = DashboardWidgetIntent(),
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetTimelineEntry {
        WidgetTimelineEntry(
            date: now(),
            presentation: FictionalDashboardPresentationSource.presentation(
                for: configuration,
                family: family
            )
        )
    }

    func snapshotEntry(
        for configuration: DashboardWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetTimelineEntry {
        WidgetTimelineFactory.snapshotEntry(
            loadResult: loader.load(),
            configuration: IntentConfigurationAdapter.dashboard(configuration),
            family: family,
            date: now(),
            calendar: calendar
        )
    }

    func widgetTimeline(
        for configuration: DashboardWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> Timeline<WidgetTimelineEntry> {
        widgetSchedule(for: configuration, family: family).timeline
    }

    func widgetSchedule(
        for configuration: DashboardWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetTimelineSchedule {
        WidgetTimelineFactory.schedule(
            loadResult: loader.load(),
            configuration: IntentConfigurationAdapter.dashboard(configuration),
            family: family,
            now: now(),
            calendar: calendar
        )
    }
}

struct DashboardTimelineEntryView: View {
    let entry: WidgetTimelineEntry

    var body: some View {
        if let presentation = entry.presentation {
            DashboardWidgetView(
                presentation: presentation,
                nowEpoch: Int(entry.date.timeIntervalSince1970)
            )
        } else if let state = entry.state {
            WidgetTimelineStateView(state: state)
        }
    }
}
