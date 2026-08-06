import AgentMeterWidgetCore
import Foundation
import SwiftUI
import WidgetKit

enum WidgetSnapshotLoadResult: Equatable, Sendable {
    case snapshot(WidgetSnapshot)
    case notConfigured
    case unavailable
    case updateRequired
}

struct WidgetSnapshotLoader: Sendable {
    static let appGroupIdentifier = "group.com.prabhavalabs.agentmeter.shared"

    private let store: WidgetSnapshotStore?

    init() {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            store = nil
            return
        }
        store = WidgetSnapshotStore(directoryURL: directory)
    }

    init(store: WidgetSnapshotStore) {
        self.store = store
    }

    func load() -> WidgetSnapshotLoadResult {
        guard let store else { return .notConfigured }
        do {
            guard let snapshot = try store.load() else { return .notConfigured }
            return .snapshot(snapshot)
        } catch WidgetSnapshotStoreError.unsupportedSchema {
            return .updateRequired
        } catch {
            return .unavailable
        }
    }
}

enum WidgetTimelineViewState: CaseIterable, Equatable, Sendable {
    case notConfigured
    case agentUnavailable
    case unavailable
    case updateRequired

    var message: String {
        switch self {
        case .notConfigured:
            "Open AgentMeter to configure this widget"
        case .agentUnavailable, .unavailable:
            "Agent unavailable"
        case .updateRequired:
            "Update AgentMeter to view this widget"
        }
    }

    var accessibilityLabel: String { message }

    var systemImage: String {
        switch self {
        case .notConfigured: "gearshape"
        case .agentUnavailable, .unavailable: "person.crop.circle.badge.exclamationmark"
        case .updateRequired: "arrow.down.app"
        }
    }
}

struct WidgetTimelineEntry: TimelineEntry, Equatable, Sendable {
    let date: Date
    let presentation: WidgetPresentation?
    let state: WidgetTimelineViewState?

    init(date: Date, presentation: WidgetPresentation) {
        self.date = date
        self.presentation = presentation
        state = nil
    }

    init(date: Date, state: WidgetTimelineViewState) {
        self.date = date
        presentation = nil
        self.state = state
    }

    init(
        date: Date,
        dashboardPresentation: WidgetPresentation? = nil,
        focusPresentation: WidgetPresentation? = nil
    ) {
        self.date = date
        presentation = dashboardPresentation ?? focusPresentation
        state = presentation == nil ? .agentUnavailable : nil
    }
}

typealias FictionalUsageEntry = WidgetTimelineEntry

enum AgentMeterTimelineReloadPolicy: Equatable, Sendable {
    case after(Date)

    var widgetKitPolicy: TimelineReloadPolicy {
        switch self {
        case let .after(date): .after(date)
        }
    }
}

struct WidgetTimelineSchedule: Equatable, Sendable {
    let entries: [WidgetTimelineEntry]
    let reloadPolicy: AgentMeterTimelineReloadPolicy

    var timeline: Timeline<WidgetTimelineEntry> {
        Timeline(entries: entries, policy: reloadPolicy.widgetKitPolicy)
    }
}

struct WidgetTimelineStateView: View {
    let state: WidgetTimelineViewState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.16), Color.secondary.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            WidgetStateView(title: state.message, systemImage: state.systemImage)
                .padding()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

enum WidgetTimelineFactory {
    static let unavailableRetryInterval: TimeInterval = 15 * 60

    static func snapshotEntry(
        loadResult: WidgetSnapshotLoadResult,
        configuration: WidgetRenderConfiguration,
        family: AgentMeterWidgetCore.WidgetFamily,
        date: Date,
        calendar: Calendar
    ) -> WidgetTimelineEntry {
        switch loadResult {
        case let .snapshot(snapshot):
            return resolvedEntry(
                snapshot: snapshot,
                configuration: configuration,
                family: family,
                date: date,
                calendar: calendar
            )
        case .notConfigured:
            return WidgetTimelineEntry(date: date, state: .notConfigured)
        case .unavailable:
            return WidgetTimelineEntry(date: date, state: .unavailable)
        case .updateRequired:
            return WidgetTimelineEntry(date: date, state: .updateRequired)
        }
    }

    static func schedule(
        loadResult: WidgetSnapshotLoadResult,
        configuration: WidgetRenderConfiguration,
        family: AgentMeterWidgetCore.WidgetFamily,
        now: Date,
        calendar: Calendar
    ) -> WidgetTimelineSchedule {
        guard case let .snapshot(snapshot) = loadResult else {
            return WidgetTimelineSchedule(
                entries: [snapshotEntry(
                    loadResult: loadResult,
                    configuration: configuration,
                    family: family,
                    date: now,
                    calendar: calendar
                )],
                reloadPolicy: .after(now.addingTimeInterval(unavailableRetryInterval))
            )
        }

        let nowEpoch = Int(now.timeIntervalSince1970)
        let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, nowEpoch: nowEpoch)
        let entries = ([plan.currentEpoch] + plan.checkpoints).map { epoch in
            resolvedEntry(
                snapshot: snapshot,
                configuration: configuration,
                family: family,
                date: Date(timeIntervalSince1970: TimeInterval(epoch)),
                calendar: calendar
            )
        }
        return WidgetTimelineSchedule(
            entries: entries,
            reloadPolicy: .after(Date(timeIntervalSince1970: TimeInterval(plan.reloadAfterEpoch)))
        )
    }

    private static func resolvedEntry(
        snapshot: WidgetSnapshot,
        configuration: WidgetRenderConfiguration,
        family: AgentMeterWidgetCore.WidgetFamily,
        date: Date,
        calendar: Calendar
    ) -> WidgetTimelineEntry {
        if let selectedID = configuration.focusProviderID,
           snapshot.providers.contains(where: { $0.id == selectedID }) == false {
            return WidgetTimelineEntry(date: date, state: .agentUnavailable)
        }

        let nowEpoch = Int(date.timeIntervalSince1970)
        let endingDayEpoch = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        let presentation = WidgetPresentationResolver.resolve(
            configuration: configuration,
            snapshot: snapshot,
            family: family,
            nowEpoch: nowEpoch,
            endingAtDayEpoch: endingDayEpoch,
            calendar: calendar
        )
        guard presentation.providers.isEmpty == false else {
            return WidgetTimelineEntry(date: date, state: .agentUnavailable)
        }
        return WidgetTimelineEntry(date: date, presentation: presentation)
    }
}

extension WidgetKit.WidgetFamily {
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
