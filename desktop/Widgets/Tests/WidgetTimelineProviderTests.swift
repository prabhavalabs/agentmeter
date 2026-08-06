import AgentMeterCore
import AgentMeterWidgetCore
import Foundation
import Testing
import WidgetKit

private let fixedNow = Date(timeIntervalSince1970: 20_000)
private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

@Test func snapshotLoaderMapsMissingCorruptAndUnsupportedStoresToStableStates() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetSnapshotStore(directoryURL: directory)
    let loader = WidgetSnapshotLoader(store: store)

    #expect(loader.load() == .notConfigured)
    #expect(WidgetTimelineViewState.notConfigured.message == "Open AgentMeter to configure this widget")

    try Data("not json".utf8).write(to: store.url)
    #expect(loader.load() == .unavailable)

    try Data("""
    {"schemaVersion":2}
    """.utf8).write(to: store.url)
    #expect(loader.load() == .updateRequired)
    #expect(WidgetTimelineViewState.updateRequired.message == "Update AgentMeter to view this widget")
}

@Test func dashboardTimelineLoadsStoreAndPlansStaleAndResetEntries() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetSnapshotStore(directoryURL: directory)
    try store.writeIfChanged(snapshot(
        generatedAt: 18_000,
        providers: [provider(resetAt: 20_600)]
    ))
    let provider = DashboardTimelineProvider(
        loader: WidgetSnapshotLoader(store: store),
        now: { fixedNow },
        calendar: fixedCalendar
    )

    let timeline = provider.widgetTimeline(
        for: DashboardWidgetIntent(),
        family: .large
    )

    #expect(timeline.entries.map { Int($0.date.timeIntervalSince1970) } == [20_000, 20_600, 106_400])
    #expect(timeline.entries.first?.presentation?.freshness == .stale)
    #expect(timeline.entries.first?.presentation?.providers.first?.rings.first?.resetState == .scheduled(epoch: 20_600))
    #expect(timeline.entries[1].presentation?.providers.first?.rings.first?.resetState == .pending)
    #expect(timeline.entries[1].presentation?.providers.first?.rings.first?.resetText == "Refresh pending")
}

@Test func focusSnapshotReportsSelectedProviderAbsenceWithoutFallingBack() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetSnapshotStore(directoryURL: directory)
    try store.writeIfChanged(snapshot(providers: [provider()]))
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "missing", name: "Missing")
    let timelineProvider = FocusTimelineProvider(
        loader: WidgetSnapshotLoader(store: store),
        now: { fixedNow },
        calendar: fixedCalendar
    )

    let entry = timelineProvider.snapshotEntry(for: intent, family: .small)

    #expect(entry.presentation == nil)
    #expect(entry.state == .agentUnavailable)
    #expect(entry.state?.message == "Agent unavailable")
}

@Test func focusPresentationKeepsMissingUsageResetAndHistoryTruthful() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetSnapshotStore(directoryURL: directory)
    let windows = [
        WidgetWindowSnapshot(kind: "monthly", label: "Monthly", usedPercent: 10, resetAtEpoch: 30_000),
        WidgetWindowSnapshot(kind: "session", label: "Session", usedPercent: 20, resetAtEpoch: 25_000),
        WidgetWindowSnapshot(kind: "daily", label: "Daily", usedPercent: 30, resetAtEpoch: nil),
        WidgetWindowSnapshot(kind: "model", label: "Model", usedPercent: 40, resetAtEpoch: nil),
        WidgetWindowSnapshot(kind: "reserve", label: "Reserve", usedPercent: nil, resetAtEpoch: nil),
    ]
    try store.writeIfChanged(snapshot(providers: [provider(windows: windows)]))
    let intent = FocusWidgetIntent()
    intent.provider = ProviderEntity(id: "codex", name: "Codex")
    intent.outerWindow = WindowEntity(providerID: "codex", windowKind: "reserve", label: "Reserve")
    intent.historyStyle = .heatMap
    let timelineProvider = FocusTimelineProvider(
        loader: WidgetSnapshotLoader(store: store),
        now: { fixedNow },
        calendar: fixedCalendar
    )

    let presentation = timelineProvider.snapshotEntry(for: intent, family: .large).presentation
    let ring = try #require(presentation?.providers.first?.rings.first)

    #expect(DashboardProviderCopy.percentage(ring) == "Not reported")
    #expect(DashboardProviderCopy.reset(ring) == "Reset time unavailable")
    #expect(presentation?.history?.availabilityMessage == "History unavailable for this window")
}

@Test func productionSnapshotsUseStoreWhilePlaceholdersStayFictional() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetSnapshotStore(directoryURL: directory)
    let provider = DashboardTimelineProvider(
        loader: WidgetSnapshotLoader(store: store),
        now: { fixedNow },
        calendar: fixedCalendar
    )

    let production = provider.snapshotEntry(for: DashboardWidgetIntent(), family: .small)
    let placeholder = provider.placeholderEntry(family: .small)

    #expect(production.state == .notConfigured)
    #expect(production.state?.message == "Open AgentMeter to configure this widget")
    #expect(placeholder.presentation?.providers.isEmpty == false)
    #expect(placeholder.presentation?.providers.allSatisfy { $0.status.contains("Fictional") || $0.status.contains("Allowance") } == true)
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WidgetTimelineProviderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func snapshot(
    generatedAt: Int = 19_900,
    providers: [WidgetProviderSnapshot]
) -> WidgetSnapshot {
    WidgetSnapshot(
        generatedAtEpoch: generatedAt,
        pollIntervalSeconds: 300,
        historyStartEpoch: nil,
        providers: providers
    )
}

private func provider(
    resetAt: Int? = 30_000,
    windows: [WidgetWindowSnapshot]? = nil
) -> WidgetProviderSnapshot {
    WidgetProviderSnapshot(
        id: "codex",
        name: "Codex",
        status: "Allowance available",
        updatedAtEpoch: 19_900,
        windows: windows ?? [
            WidgetWindowSnapshot(
                kind: "weekly",
                label: "Weekly",
                usedPercent: 42,
                resetAtEpoch: resetAt
            ),
        ],
        history: []
    )
}
