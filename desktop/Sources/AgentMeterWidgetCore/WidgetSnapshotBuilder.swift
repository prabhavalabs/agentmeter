import AgentMeterCore
import Foundation

public struct WidgetSnapshotBuilder: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case encodedSizeExceedsLimit
    }

    public init() {}

    public func build(
        state: ControlState,
        summaries: [String: WidgetHistorySummary],
        hourlySummaries: [String: WidgetHourlySummary] = [:]
    ) throws -> WidgetSnapshot {
        let providers = orderedProviders(in: state)
            .prefix(WidgetSnapshot.maximumProviderCount)
            .map { provider in
                let retainedWindows = retainedWindows(provider.windows)
                let windows = retainedWindows.map(makeWindowSnapshot)
                return WidgetProviderSnapshot(
                    id: provider.id,
                    name: provider.name,
                    status: provider.status,
                    updatedAtEpoch: provider.updatedAtEpoch,
                    windows: windows,
                    history: history(
                        for: provider,
                        retainedWindows: retainedWindows,
                        summary: summaries[provider.id]
                    ),
                    hourly: hourly(
                        for: provider,
                        retainedWindows: retainedWindows,
                        summary: hourlySummaries[provider.id]
                    )
                )
            }

        let snapshot = try WidgetSnapshotCanonicalizer.canonicalize(WidgetSnapshot(
            generatedAtEpoch: generationEpoch(state: state),
            pollIntervalSeconds: state.bridge.pollIntervalSeconds,
            historyStartEpoch: historyStartEpoch(
                providerIds: providers.map(\.id),
                summaries: summaries
            ),
            providers: providers
        ))
        guard try WidgetSnapshotCoding.encode(snapshot).count <= WidgetSnapshot.maximumEncodedBytes else {
            throw Error.encodedSizeExceedsLimit
        }
        return snapshot
    }

    private func orderedProviders(in state: ControlState) -> [ProviderSummary] {
        let configuredOrder = if let settingsOrder = state.settings?.providerOrder,
                                 settingsOrder.isEmpty == false {
            settingsOrder
        } else if state.bridge.configuredProviderIds.isEmpty == false {
            state.bridge.configuredProviderIds
        } else {
            state.providers.map(\.id)
        }
        let providersById = Dictionary(
            state.providers.reversed().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let configured = configuredOrder.compactMap { id -> ProviderSummary? in
            guard seen.insert(id).inserted else { return nil }
            return providersById[id]
        }
        let remaining = state.providers.filter { seen.insert($0.id).inserted }
        return configured + remaining
    }

    private func makeWindowSnapshot(_ window: ProviderWindow) -> WidgetWindowSnapshot {
        WidgetWindowSnapshot(
            kind: window.kind,
            label: window.label,
            usedPercent: validatedPercent(window.usedPercent),
            resetAtEpoch: window.resetAtEpoch
        )
    }

    private func retainedWindows(_ windows: [ProviderWindow]) -> [ProviderWindow] {
        var seen = Set<String>()
        return Array(windows.compactMap { window in
            seen.insert(window.kind).inserted ? window : nil
        }.prefix(WidgetSnapshot.maximumWindowCountPerProvider))
    }

    private func history(
        for provider: ProviderSummary,
        retainedWindows: [ProviderWindow],
        summary: WidgetHistorySummary?
    ) -> [WidgetHistoryDay] {
        guard let summary else { return [] }

        let validDays = summary.days.filter {
            $0.providerId == provider.id && $0.consumedPercentPoints >= 0
        }

        let selectedKinds = WidgetWindowSelector.historyEnabledKinds(from: retainedWindows)
        let kindOrder = Dictionary(uniqueKeysWithValues: selectedKinds.enumerated().map { ($1, $0) })

        var retained: [WidgetHistoryDay] = []
        for kind in selectedKinds {
            var byDay: [Int: WidgetHistoryDay] = [:]
            for day in validDays where day.windowKind == kind {
                let candidate = makeHistoryDaySnapshot(day)
                if let existing = byDay[day.dayStartEpoch] {
                    byDay[day.dayStartEpoch] = WidgetSnapshotCanonicalizer.preferredHistoryDay(
                        existing,
                        candidate
                    )
                } else {
                    byDay[day.dayStartEpoch] = candidate
                }
            }
            retained.append(contentsOf: byDay.values
                .sorted { $0.dayStartEpoch > $1.dayStartEpoch }
                .prefix(WidgetSnapshot.maximumHistoryDayCount))
        }

        return retained
            .sorted {
                if $0.dayStartEpoch != $1.dayStartEpoch {
                    return $0.dayStartEpoch < $1.dayStartEpoch
                }
                let leftKind = kindOrder[$0.windowKind] ?? .max
                let rightKind = kindOrder[$1.windowKind] ?? .max
                if leftKind != rightKind { return leftKind < rightKind }
                return $0.windowKind < $1.windowKind
            }
    }

    private func hourly(
        for provider: ProviderSummary,
        retainedWindows: [ProviderWindow],
        summary: WidgetHourlySummary?
    ) -> [WidgetHourlyPoint] {
        guard let summary else { return [] }
        let retainedKinds = Set(retainedWindows.map(\.kind))
        var byKind: [String: [WidgetHourlyPoint]] = [:]
        for point in summary.hours
        where point.providerId == provider.id
            && retainedKinds.contains(point.windowKind)
            && (0...100).contains(point.latestUsedPercent)
            && point.hourStartEpoch >= 0 {
            byKind[point.windowKind, default: []].append(point)
        }
        return byKind.values.flatMap { points in
            points
                .sorted { $0.hourStartEpoch < $1.hourStartEpoch }
                .suffix(WidgetSnapshot.maximumHourlyPointCountPerWindow)
        }
    }

    private func makeHistoryDaySnapshot(_ day: WidgetHistoryDay) -> WidgetHistoryDay {
        WidgetHistoryDay(
            providerId: day.providerId,
            windowKind: day.windowKind,
            dayStartEpoch: day.dayStartEpoch,
            consumedPercentPoints: day.consumedPercentPoints,
            latestUsedPercent: validatedPercent(day.latestUsedPercent),
            resetAtEpoch: day.resetAtEpoch,
            cycleStartEpoch: day.cycleStartEpoch
        )
    }

    private func validatedPercent(_ value: Int?) -> Int? {
        value.flatMap { (0...100).contains($0) ? $0 : nil }
    }

    private func historyStartEpoch(
        providerIds: [String],
        summaries: [String: WidgetHistorySummary]
    ) -> Int? {
        providerIds.compactMap { summaries[$0]?.historyStartEpoch }.min()
    }

    private func generationEpoch(state: ControlState) -> Int {
        let providerEpochs = state.providers.compactMap(\.updatedAtEpoch)
        return ([state.bridge.lastProviderRefreshEpoch].compactMap { $0 } + providerEpochs).max() ?? 0
    }
}
