import AgentMeterWidgetCore
import Foundation
import SwiftUI
import WidgetKit

struct FocusTimelineProvider: AppIntentTimelineProvider {
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
        for configuration: FocusWidgetIntent,
        in context: Context
    ) async -> WidgetTimelineEntry {
        if context.isPreview {
            return placeholderEntry(for: configuration, family: context.family.presentationFamily)
        }
        return snapshotEntry(for: configuration, family: context.family.presentationFamily)
    }

    func timeline(
        for configuration: FocusWidgetIntent,
        in context: Context
    ) async -> Timeline<WidgetTimelineEntry> {
        widgetTimeline(for: configuration, family: context.family.presentationFamily)
    }

    func placeholderEntry(
        for configuration: FocusWidgetIntent = FocusWidgetIntent(),
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetTimelineEntry {
        WidgetTimelineEntry(
            date: now(),
            presentation: FictionalFocusPresentationSource.presentation(
                for: configuration,
                family: family
            )
        )
    }

    func snapshotEntry(
        for configuration: FocusWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetTimelineEntry {
        WidgetTimelineFactory.snapshotEntry(
            loadResult: loader.load(),
            configuration: IntentConfigurationAdapter.focus(configuration),
            family: family,
            date: now(),
            calendar: calendar
        )
    }

    func widgetTimeline(
        for configuration: FocusWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> Timeline<WidgetTimelineEntry> {
        widgetSchedule(for: configuration, family: family).timeline
    }

    func widgetSchedule(
        for configuration: FocusWidgetIntent,
        family: AgentMeterWidgetCore.WidgetFamily
    ) -> WidgetTimelineSchedule {
        WidgetTimelineFactory.schedule(
            loadResult: loader.load(),
            configuration: IntentConfigurationAdapter.focus(configuration),
            family: family,
            now: now(),
            calendar: calendar
        )
    }
}

struct FocusTimelineEntryView: View {
    let entry: WidgetTimelineEntry

    var body: some View {
        if let presentation = entry.presentation {
            FocusWidgetView(presentation: presentation)
        } else if let state = entry.state {
            WidgetTimelineStateView(state: state)
        }
    }
}
